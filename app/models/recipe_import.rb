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

  def start!
    update!(status: :running, started_at: Time.current)
  end

  # Keeps what the scraper found and saves it as a recipe, exactly as the import
  # did when it ran inside the request. A title already in the box, or a recipe that
  # fails validation, is not saved: the waiting page then redirects to the existing
  # recipe, or opens the pre-filled form with the errors.
  def succeed!(scraped)
    self.data = scraped
    recipe = save_recipe
    update!(status: :succeeded, recipe_id: recipe&.id, finished_at: Time.current)
  end

  def fail!(error)
    update!(status: :failed, error: error.to_s, finished_at: Time.current)
  end

  def stalled?
    (queued? || running?) && created_at < STALLED_AFTER.ago
  end

  # The scraped recipe as the scraper returned it: symbol keys all the way down.
  def recipe_data
    data.to_h.deep_symbolize_keys
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
    return FAILURE_MESSAGES.fetch(:busy) if stalled?

    FAILURE_MESSAGES.fetch(error.to_s.to_sym, DEFAULT_FAILURE_MESSAGE)
  end

  private

  def save_recipe
    return if existing_recipe_with_title

    recipe = build_recipe
    saved = RecipeIngredient.without_aisle_sync { recipe.save }
    recipe.resync_aisle_mappings! if saved
    recipe if saved
  end
end
