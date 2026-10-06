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

  def succeed!(recipe)
    update!(status: :succeeded, data: recipe, finished_at: Time.current)
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

  def failure_message
    return FAILURE_MESSAGES.fetch(:busy) if stalled?

    FAILURE_MESSAGES.fetch(error.to_s.to_sym, DEFAULT_FAILURE_MESSAGE)
  end
end
