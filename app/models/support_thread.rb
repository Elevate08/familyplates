class SupportThread < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :household
  belongs_to :created_by_user, class_name: "User", optional: true
  has_many :messages, class_name: "SupportMessage", dependent: :destroy

  enum :status, {
    open: "open",
    waiting_on_customer: "waiting_on_customer",
    waiting_on_support: "waiting_on_support",
    resolved: "resolved"
  }, validate: true

  validates :subject, presence: true, length: { maximum: 200 }

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
end
