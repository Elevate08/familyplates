class PlatformAuditEvent < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :platform_admin, class_name: "PlatformAdminAccount", optional: true

  validates :action, presence: true

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
end
