# frozen_string_literal: true

require "securerandom"

class Session < ApplicationRecord
  ACTIVITY_REFRESH_RATE = 1.hour
  IDLE_TIMEOUT = 30.days
  ABSOLUTE_TIMEOUT = 90.days

  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :user
  has_one :device_grant, dependent: :nullify

  enum :kind, %w[browser kiosk].index_by(&:itself), default: :browser, validate: true

  validates :token, presence: true, uniqueness: true
  validates :last_active_at, presence: true

  before_validation :set_defaults, on: :create

  def resume(user_agent:, ip_address:)
    return if last_active_at && last_active_at >= ACTIVITY_REFRESH_RATE.ago

    update_columns(
      user_agent: user_agent,
      ip_address: ip_address,
      last_active_at: Time.current,
      updated_at: Time.current
    )
  end

  def expired?
    return false if kiosk?

    idle_expired? || absolute_expired?
  end

  def idle_expired?
    last_active_at.nil? || last_active_at < IDLE_TIMEOUT.ago
  end

  def absolute_expired?
    created_at.nil? || created_at < ABSOLUTE_TIMEOUT.ago
  end

  private

  def set_defaults
    self.token ||= SecureRandom.hex(32)
    self.last_active_at ||= Time.current
  end
end
