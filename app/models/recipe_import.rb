# One recipe import, from the moment someone pastes a link until the waiting
# page has shown them the result. RecipeImportJob fetches the page in the
# background and records what it found here; the page reads it from here.
class RecipeImport < ApplicationRecord
  # "Could not fetch recipe" covered a site refusing bots, a dead link, and a
  # page with no recipe on it alike, which left the user with nothing to act on.
  FAILURE_MESSAGES = {
    blocked_by_site: "That site blocks automatic recipe imports. Try copying the recipe in manually, or import it from another site.",
    timeout: "That site took too long to respond. Please try again in a moment, or add the recipe manually.",
    not_found: "That recipe page no longer exists. Please double-check the link.",
    site_error: "That site is having trouble right now. Please try again later, or add the recipe manually.",
    busy: "Recipe import is busy right now. Please try again in a moment.",
    unparseable: "We couldn't find a recipe on that page. Make sure the link points at the recipe itself, or add it manually."
    # :blocked (egress policy) deliberately has no entry: an address this server
    # is not allowed to reach must look exactly like any other bad link, or the
    # message becomes a probe for what is reachable from inside the network.
  }.freeze

  DEFAULT_FAILURE_MESSAGE = "Could not fetch recipe from that web address. Please check the link or add manually."

  # A fetch is cut off after 20 seconds, so an import still waiting after this
  # long was never picked up (no worker running, or it died mid-fetch).
  STALLED_AFTER = 5.minutes

  # Rows only exist to be read by the waiting page.
  RETENTION = 1.day

  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :household
  belongs_to :family_member, optional: true

  enum :status, %w[queued running succeeded failed].index_by(&:itself), default: :queued, validate: true

  validates :url, presence: true

  scope :expired, -> { where(created_at: ...RETENTION.ago) }

  # The job's claim on a queued import. Only one caller gets true, and an import
  # already failed as stalled is never started, so it cannot run after the person
  # was told it failed.
  def claim!
    now = Time.current
    claimed = self.class.where(id: id, status: "queued").update_all(status: "running", started_at: now, updated_at: now) == 1
    reload
    claimed
  end

  # Keeps what the scraper found and saves it as a recipe, exactly as the import
  # did when it ran inside the request. A title already in the box, or a recipe that
  # fails validation, is not saved: the waiting page then redirects to the existing
  # recipe, or opens the pre-filled form with the errors.
  #
  # The recipe and the succeeded status are written together. The aisle resync
  # runs after that and only logs a failure: a recipe that was saved is never
  # reported as a failed import.
  def succeed!(scraped)
    self.data = scraped
    recipe = transaction do
      saved = save_recipe
      update!(status: :succeeded, recipe_id: saved&.id, finished_at: Time.current)
      saved
    end
    resync_aisle_mappings(recipe)
  end

  def fail!(error)
    update!(status: :failed, error: error.to_s, finished_at: Time.current)
  end

  # Queued imports wait from created_at; running ones from started_at, so time
  # spent queued behind another import is not held against the fetch.
  def stalled?
    waiting_since = queued? ? created_at : started_at
    (queued? || running?) && waiting_since.present? && waiting_since < STALLED_AFTER.ago
  end

  # Fails an unfinished import as busy, once the waiting page has given up on it.
  def stall!
    now = Time.current
    self.class.where(id: id, status: %w[queued running]).update_all(status: "failed", error: "busy", finished_at: now, updated_at: now)
    reload
  end

  # The scraped recipe as the scraper returned it: symbol keys all the way down.
  def recipe_data
    @recipe_data ||= data.to_h.deep_symbolize_keys
  end

  def data=(value)
    @recipe_data = nil
    super
  end

  def reload(*)
    @recipe_data = nil
    super
  end

  def existing_recipe_with_title
    household.recipes.where("LOWER(title) = ?", recipe_data[:title].to_s.strip.downcase).first
  end

  # An unsaved recipe built from the scraped data.
  def build_recipe
    data = recipe_data
    recipe = household.recipes.build(
      title: data[:title].presence || "Imported Recipe",
      description: data[:description],
      prep_time: data[:prep_time],
      cook_time: data[:cook_time],
      total_time: data[:total_time],
      equipment: data[:equipment],
      servings: data[:servings] || RecipeScraper::DEFAULT_SERVINGS,
      source_url: data[:source_url],
      image_url: data[:image_url],
      instructions: data[:instructions]
    )

    Array(data[:ingredients]).each do |ing|
      recipe.recipe_ingredients.build(
        raw_text: ing[:raw_text],
        name: ing[:name],
        quantity: ing[:quantity],
        unit: ing[:unit],
        # nil, not "Other" - the model classifies when no aisle is supplied,
        # and cannot tell a scraper default from a user's deliberate choice.
        aisle_category: ing[:aisle_category].presence
      )
    end
    recipe
  end

  def failure_message
    FAILURE_MESSAGES.fetch(error.to_s.to_sym, DEFAULT_FAILURE_MESSAGE)
  end

  private

  def save_recipe
    return if existing_recipe_with_title

    recipe = build_recipe
    recipe if RecipeIngredient.without_aisle_sync { recipe.save }
  end

  def resync_aisle_mappings(recipe)
    recipe&.resync_aisle_mappings!
  rescue StandardError => e
    Rails.logger.error("[import] aisle resync failed for recipe_id=#{recipe.id}: #{e.class}")
  end
end
