class PlatformAdminSession < ApplicationRecord
  IDLE_TIMEOUT = 12.hours
  ABSOLUTE_TIMEOUT = 30.days

  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :platform_admin, class_name: "PlatformAdminAccount", foreign_key: :platform_admin_id

  validates :token, presence: true, uniqueness: true
  validates :last_active_at, presence: true

  before_validation :set_defaults, on: :create

  def expired?
    last_active_at < IDLE_TIMEOUT.ago || created_at < ABSOLUTE_TIMEOUT.ago
  end

  def resume(user_agent:, ip_address:)
    update_columns(
      user_agent: user_agent,
      ip_address: ip_address,
      last_active_at: Time.current,
      updated_at: Time.current
    )
  end

  private

  def set_defaults
    self.token ||= SecureRandom.hex(32)
    self.last_active_at ||= Time.current
  end
end
