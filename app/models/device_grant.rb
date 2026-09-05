# frozen_string_literal: true

require "securerandom"

class DeviceGrant < ApplicationRecord
  DEFAULT_LIFETIME = 15.minutes
  DEFAULT_INTERVAL = 5

  # Base20-style alphabet omitting visually ambiguous characters (0, O, 1, I, L, 8, B)
  USER_CODE_CHARACTERS = %w[2 3 4 5 6 7 9 A C D E F G H J K M N P Q R T V W X Y Z].freeze

  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :household, optional: true
  belongs_to :user, optional: true
  belongs_to :session, optional: true

  enum :kind, %w[kiosk browser].index_by(&:itself), default: :kiosk, validate: true
  enum :status, %w[pending approved denied expired].index_by(&:itself), default: :pending, validate: true

  validates :device_code, presence: true, uniqueness: true
  validates :user_code, presence: true, uniqueness: true
  validates :expires_at, presence: true

  before_validation :set_defaults, on: :create

  def self.normalize_user_code(code)
    code.to_s.gsub(/[^A-Za-z0-9]/, "").upcase
  end

  def self.find_by_user_code(raw_code)
    normalized = normalize_user_code(raw_code)
    return nil if normalized.blank?

    find_by("REPLACE(user_code, '-', '') = ?", normalized)
  end

  def expired?
    expires_at <= Time.current
  end

  def pending?
    status == "pending" && !expired?
  end

  def approved?
    status == "approved" && session.present?
  end

  def denied?
    status == "denied"
  end

  def expires_in_seconds
    [ ((expires_at - Time.current).to_i), 0 ].max
  end

  def interval_seconds
    DEFAULT_INTERVAL
  end

  def polling_too_fast?
    last_polled_at.present? && last_polled_at > (interval_seconds - 1).seconds.ago
  end

  def approve!(by:, household: nil, kind: nil)
    raise "Grant is no longer pending" unless pending?

    target_kind = kind.presence || self.kind.presence || "kiosk"
    target_household = household || by.households.first || Household.installation

    transaction do
      created_session = by.sessions.create!(
        token: SecureRandom.hex(32),
        kind: target_kind,
        ip_address: ip_address,
        user_agent: user_agent,
        last_active_at: Time.current
      )

      update!(
        status: "approved",
        approved_at: Time.current,
        user: by,
        household: target_household,
        session: created_session,
        kind: target_kind
      )
    end
  end

  def deny!
    update!(status: "denied")
  end

  private

  def set_defaults
    self.device_code ||= SecureRandom.hex(32)
    self.user_code ||= generate_unique_user_code
    self.expires_at ||= DEFAULT_LIFETIME.from_now
    self.status ||= "pending"
    self.kind ||= "kiosk"
  end

  def generate_unique_user_code
    loop do
      part1 = Array.new(4) { USER_CODE_CHARACTERS.sample(random: SecureRandom) }.join
      part2 = Array.new(4) { USER_CODE_CHARACTERS.sample(random: SecureRandom) }.join
      code = "#{part1}-#{part2}"
      return code unless DeviceGrant.exists?(user_code: code)
    end
  end
end
