class SupportThread < ApplicationRecord
  # "open" is the pre-rename value for waiting_on_support; keep it queryable so
  # older rows still show up in operator and customer inboxes.
  LEGACY_OPEN_STATUS = "open"
  ACTIVE_STATUSES = %w[waiting_on_support waiting_on_customer open].freeze
  WAITING_ON_SUPPORT_STATUSES = %w[waiting_on_support open].freeze
  OPERATOR_SETTABLE_STATUSES = %w[waiting_on_support waiting_on_customer resolved].freeze

  attribute :id, default: -> { SecureRandom.uuid }
  attribute :status, default: "waiting_on_support"

  belongs_to :household
  belongs_to :created_by_user, class_name: "User", optional: true
  has_many :messages, class_name: "SupportMessage", dependent: :destroy, inverse_of: :thread

  enum :status, {
    open: "open",
    waiting_on_customer: "waiting_on_customer",
    waiting_on_support: "waiting_on_support",
    resolved: "resolved"
  }, validate: true

  validates :subject, presence: true, length: { maximum: 200 }

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :waiting_on_support_only, -> { where(status: WAITING_ON_SUPPORT_STATUSES) }
  scope :waiting_on_customer_only, -> { where(status: "waiting_on_customer") }
  scope :resolved_only, -> { where(status: "resolved") }

  def self.display_status_for(status)
    status.to_s == LEGACY_OPEN_STATUS ? "waiting_on_support" : status.to_s
  end

  def display_status
    self.class.display_status_for(status)
  end

  def active?
    !resolved?
  end

  def record_message!(message)
    update_columns(
      status: message.platform_admin? ? "waiting_on_customer" : "waiting_on_support",
      last_message_at: message.created_at,
      resolved_at: nil,
      updated_at: Time.current
    )
  end

  def resolve!
    update!(status: :resolved, resolved_at: Time.current)
  end

  def reopen!(by: nil)
    status_to_set = by.is_a?(PlatformAdminAccount) ? :waiting_on_customer : :waiting_on_support
    update!(status: status_to_set, resolved_at: nil)
  end

  def change_status!(new_status)
    return false unless OPERATOR_SETTABLE_STATUSES.include?(new_status.to_s)

    attrs = { status: new_status }
    attrs[:resolved_at] = (new_status.to_s == "resolved" ? Time.current : nil)
    update!(attrs)
  end
end
