class PlatformAdminAccount < ApplicationRecord
  self.table_name = "platform_admins"

  attribute :id, default: -> { SecureRandom.uuid }

  has_secure_password validations: false
  has_many :sessions, class_name: "PlatformAdminSession", foreign_key: :platform_admin_id, dependent: :destroy

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :password, presence: true, on: :create
  validates :role, inclusion: { in: %w[owner support billing privacy] }

  before_validation :generate_otp_secret, on: :create

  def active?
    active
  end

  def valid_totp?(value, at: Time.current)
    normalized = value.to_s.strip
    return false unless normalized.match?(/\A\d{6}\z/)

    (-1..1).any? do |offset|
      ActiveSupport::SecurityUtils.secure_compare(
        self.class::Totp.code(otp_secret, at: at + offset * Totp::STEP), normalized
      )
    end
  end

  module Totp
    extend self

    STEP = 30
    DIGITS = 6
    SECRET_BYTES = 20
    ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"

    def secret
      encode(SecureRandom.random_bytes(SECRET_BYTES))
    end

    def code(secret, at: Time.current)
      counter = Integer(at.to_i / STEP)
      digest = OpenSSL::HMAC.digest("SHA1", decode(secret), [ counter ].pack("Q>"))
      offset = digest.getbyte(-1) & 0x0f
      binary = digest.byteslice(offset, 4).unpack1("N") & 0x7fffffff
      format("%0*d", DIGITS, binary % (10**DIGITS))
    end

    def provisioning_uri(secret, email:, issuer: "FamilyPlates")
      label = "#{issuer}:#{email}"
      "otpauth://totp/#{URI.encode_www_form_component(label)}?secret=#{secret}&issuer=#{URI.encode_www_form_component(issuer)}&algorithm=SHA1&digits=#{DIGITS}&period=#{STEP}"
    end

    private

    def encode(bytes)
      buffer = 0
      bits = 0
      output = +""
      bytes.each_byte do |byte|
        buffer = (buffer << 8) | byte
        bits += 8
        while bits >= 5
          bits -= 5
          output << ALPHABET[(buffer >> bits) & 31]
        end
      end
      output << ALPHABET[(buffer << (5 - bits)) & 31] if bits.positive?
      output
    end

    def decode(value)
      buffer = 0
      bits = 0
      output = +""
      value.to_s.upcase.each_char do |character|
        index = ALPHABET.index(character)
        raise ArgumentError, "Invalid TOTP secret" unless index

        buffer = (buffer << 5) | index
        bits += 5
        next if bits < 8

        bits -= 8
        output << ((buffer >> bits) & 255)
      end
      output
    end
  end

  private

  def generate_otp_secret
    self.otp_secret ||= Totp.secret
  end
end
