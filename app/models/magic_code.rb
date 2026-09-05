# frozen_string_literal: true

require "securerandom"

class MagicCode < ApplicationRecord
  EXPIRATION_TIME = 15.minutes

  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :user, optional: true

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, :code, :expires_at, presence: true
  validates :code, format: { with: /\A[A-Z0-9]{6}\z/, message: "must be a 6-character alphanumeric code" }

  scope :active, -> { where("expires_at > ?", Time.current) }

  before_validation :set_defaults, on: :create

  BASE32_ALPHABET = %w[2 3 4 5 6 7 A B C D E F G H J K L M N P Q R S T U V W X Y Z].freeze

  def self.generate_code
    Array.new(6) { BASE32_ALPHABET.sample(random: SecureRandom) }.join
  end

  def self.for_unknown_email(email)
    new(
      id: SecureRandom.uuid,
      email: email,
      code: generate_code,
      expires_at: EXPIRATION_TIME.from_now
    )
  end

  def expired?
    expires_at <= Time.current
  end

  private

  def set_defaults
    self.code ||= self.class.generate_code
    self.expires_at ||= EXPIRATION_TIME.from_now
  end
end
