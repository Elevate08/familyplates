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

  test "generates an MFA secret and verifies current TOTP codes" do
    admin = PlatformAdminAccount.create!(email: "operator@example.com", password: "correct horse battery staple")

    assert_match(/\A[A-Z2-7]{16,}\z/, admin.otp_secret)
    assert admin.valid_totp?(PlatformAdminAccount::Totp.code(admin.otp_secret, at: Time.current))
    assert_not admin.valid_totp?("000000")
  end
end
