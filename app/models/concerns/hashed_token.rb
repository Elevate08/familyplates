# frozen_string_literal: true

require "openssl"
require "securerandom"

# Bearer tokens: store only the SHA-256 digest so a leaked backup cannot be replayed as a cookie.
# The raw token stays in memory only long enough to set the cookie. SHA-256, not bcrypt:
# 256 random bits are not brute-forced, and every request looks the digest up by unique index.
module HashedToken
  extend ActiveSupport::Concern

  included do
    validates :token_digest, presence: true, uniqueness: true
  end

  class_methods do
    def digest_token(raw)
      OpenSSL::Digest::SHA256.hexdigest(raw.to_s)
    end

    def find_by_token(raw)
      return nil if raw.blank?

      find_by(token_digest: digest_token(raw))
    end
  end

  # Only set on the instance that generated or was handed the token.
  attr_reader :token

  def token=(raw)
    @token = raw
    self.token_digest = raw.nil? ? nil : self.class.digest_token(raw)
  end

  # Mints a fresh token, replacing the stored digest, and returns it. This is
  # how a token is handed to a party that was not present when the record was
  # created (a paired device collecting its session); the old one stops working.
  def regenerate_token!
    self.token = SecureRandom.hex(32)
    update_column(:token_digest, token_digest)
    token
  end

  private

  def assign_default_token
    self.token = SecureRandom.hex(32) if token_digest.blank?
  end
end
