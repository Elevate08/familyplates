require "test_helper"

class PlatformAdminAccountTest < ActiveSupport::TestCase
  test "requires a unique email and password" do
    admin = PlatformAdminAccount.create!(email: "operator@example.com", password: "correct horse battery staple")

    assert admin.valid?
    assert admin.authenticate("correct horse battery staple")

    duplicate = PlatformAdminAccount.new(email: "OPERATOR@example.com", password: "another password")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], "has already been taken"
  end

  # @card-46.2
  test "generates an MFA secret and verifies current TOTP codes" do
    admin = PlatformAdminAccount.create!(email: "operator@example.com", password: "correct horse battery staple")

    assert_match(/\A[A-Z2-7]{16,}\z/, admin.otp_secret)
    assert admin.valid_totp?(PlatformAdminAccount::Totp.code(admin.otp_secret, at: Time.current))
    assert_not admin.valid_totp?("000000")
  end

  # FP-APPSEC-010
  test "stores the MFA secret encrypted but reads it back as the base32 secret" do
    admin = PlatformAdminAccount.create!(email: "encrypted@example.com", password: "correct horse battery staple")
    secret = admin.otp_secret
    raw = PlatformAdminAccount.connection.select_value(
      "SELECT otp_secret FROM platform_admins WHERE id = #{PlatformAdminAccount.connection.quote(admin.id)}"
    )

    assert_not_equal secret, raw
    assert_not_includes raw, secret
    assert_equal secret, admin.reload.otp_secret
    assert admin.valid_totp?(PlatformAdminAccount::Totp.code(secret))
  end

  test "a legacy plaintext secret is still readable and is encrypted on the next write" do
    admin = PlatformAdminAccount.create!(email: "legacy@example.com", password: "correct horse battery staple")
    plain = PlatformAdminAccount::Totp.secret
    PlatformAdminAccount.connection.execute(
      "UPDATE platform_admins SET otp_secret = #{PlatformAdminAccount.connection.quote(plain)} WHERE id = #{PlatformAdminAccount.connection.quote(admin.id)}"
    )

    legacy = PlatformAdminAccount.find(admin.id)
    assert_equal plain, legacy.otp_secret

    legacy.encrypt
    raw = PlatformAdminAccount.connection.select_value(
      "SELECT otp_secret FROM platform_admins WHERE id = #{PlatformAdminAccount.connection.quote(admin.id)}"
    )
    assert_not_includes raw, plain
    assert_equal plain, PlatformAdminAccount.find(admin.id).otp_secret
  end
end
