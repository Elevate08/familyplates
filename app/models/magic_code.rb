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

  MAX_FAILED_ATTEMPTS = 5

  before_validation :set_defaults, on: :create
  # Only the newest code for an address is ever live.
  before_create :retire_prior_codes

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

  # Redeems a code for an address. Returns the (now consumed) record, or nil.
  # Attempts count against the live code they were aimed at, not the
  # address, and each is counted before it is compared, so a burst of
  # parallel guesses gets no more than MAX_FAILED_ATTEMPTS comparisons. The
  # code is destroyed once its attempts are spent. A code issued afterwards
  # starts with none spent, so guessing at someone's address cannot keep
  # them from signing in, only cost them the code being guessed.
  def self.redeem(email:, code:)
    email = email.to_s.strip.downcase
    return nil if email.blank?

    # Only the newest code for an address is ever live (retire_prior_codes).
    live = active.find_by(email: email)
    return nil unless live

    attempts = attempt_store.increment(failure_key(live.id), 1, expires_in: EXPIRATION_TIME).to_i
    if attempts > MAX_FAILED_ATTEMPTS
      where(id: live.id).delete_all
      return nil
    end

    unless ActiveSupport::SecurityUtils.secure_compare(live.code, code.to_s.strip.upcase)
      where(id: live.id).delete_all if attempts >= MAX_FAILED_ATTEMPTS
      return nil
    end

    # Atomic claim: only the caller whose DELETE removes the row wins.
    return nil unless where(id: live.id).delete_all == 1

    where(email: email).delete_all
    attempt_store.delete(failure_key(live.id))
    live
  end

  def self.attempt_store
    Rails.application.config.pin_attempt_store
  end

  def self.failure_key(code_id)
    "magic_code_failures:#{code_id}"
  end

  def expired?
    expires_at <= Time.current
  end

  private

  def retire_prior_codes
    self.class.where(email: email).delete_all
  end

  def set_defaults
    self.code ||= self.class.generate_code
    self.expires_at ||= EXPIRATION_TIME.from_now
  end
end
