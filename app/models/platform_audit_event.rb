class PlatformAuditEvent < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :platform_admin, class_name: "PlatformAdminAccount", optional: true

  validates :action, presence: true

  scope :without_views, -> { where.not("action LIKE ? OR action LIKE ?", "%.viewed", "%.indexed") }

  scope :for_category, ->(category) {
    case category.to_s
    when "changes" then without_views
    when "auth" then where("action LIKE ?", "platform_admin.%")
    when "households" then where("action LIKE ?", "household%")
    when "support" then where("action LIKE ?", "support_thread.%")
    when "promotions" then where("action LIKE ?", "promotion_program.%")
    else all
    end
  }

  scope :search, ->(query) {
    return all if query.blank?

    pattern = "%#{query.strip}%"
    where(
      "action LIKE :p OR target_type LIKE :p OR target_id LIKE :p OR ip_address LIKE :p OR metadata LIKE :p",
      p: pattern
    )
  }

  def self.record!(action:, actor: nil, target: nil, metadata: {}, request: nil)
    create!(
      action: action,
      platform_admin: actor,
      target_type: target&.class&.base_class&.name,
      target_id: target&.id&.to_s,
      metadata: metadata.stringify_keys,
      ip_address: request&.remote_ip,
      user_agent: request&.user_agent
    )
  end

  def view_event?
    action.end_with?(".viewed", ".indexed")
  end
end
