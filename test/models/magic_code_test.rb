require "test_helper"

class MagicCodeTest < ActiveSupport::TestCase
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  test "generates a 6-character code and 15-minute expiry on create" do
    magic_code = MagicCode.create!(email: "  User@Example.COM ")

    assert_match UUID_PATTERN, magic_code.id
    assert_equal "user@example.com", magic_code.email
    assert_match(/\A[A-Z0-9]{6}\z/, magic_code.code)
    assert_not magic_code.expired?
    assert magic_code.expires_at > Time.current
    assert magic_code.expires_at <= 15.minutes.from_now + 5.seconds
  end

  test "active scope excludes expired codes" do
    active = MagicCode.create!(email: "active@example.com", code: "ACT123", expires_at: 10.minutes.from_now)
    expired = MagicCode.create!(email: "expired@example.com", code: "EXP123", expires_at: 1.minute.ago)

    assert_includes MagicCode.active, active
    assert_not_includes MagicCode.active, expired
  end

  test "for_unknown_email returns an unpersisted code" do
    fake = MagicCode.for_unknown_email("stranger@example.com")

    assert_not fake.persisted?
    assert_equal "stranger@example.com", fake.email
    assert_match(/\A[A-Z0-9]{6}\z/, fake.code)
    assert_not fake.expired?
  end
end
