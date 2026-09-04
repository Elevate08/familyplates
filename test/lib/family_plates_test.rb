require "test_helper"

class FamilyPlatesTest < ActiveSupport::TestCase
  setup do
    FamilyPlates.config.reset!
  end

  teardown do
    FamilyPlates.config.reset!
  end

  test "defaults to appliance mode and unrequired login" do
    assert_equal "appliance", FamilyPlates.config.mode
    assert FamilyPlates.config.appliance?
    assert_not FamilyPlates.config.hosted?
    assert_equal false, FamilyPlates.config.require_login
  end

  test "prevent enabling REQUIRE_LOGIN when no admin profile has a password" do
    household = households(:one)
    household.family_members.update_all(user_id: nil)

    assert_not household.can_require_login?
    assert_raises(FamilyPlates::AdminPasswordRequiredError) do
      FamilyPlates.config.require_login = true
    end
  end

  test "allows enabling REQUIRE_LOGIN when at least one admin has a password" do
    household = households(:one)
    admin_member = household.family_members.find_by!(role: "admin")
    admin_user = User.create!(email: "admin@example.com", password: "admin-password-123")
    admin_member.update!(user: admin_user)

    assert household.can_require_login?
    assert_nothing_raised do
      FamilyPlates.config.require_login = true
    end
    assert_equal true, FamilyPlates.config.require_login
  end

  test "outbound email validation fails fast in hosted mode without smtp settings" do
    FamilyPlates.config.mode = "hosted"

    original_method = ActionMailer::Base.delivery_method
    original_settings = ActionMailer::Base.smtp_settings
    begin
      ActionMailer::Base.delivery_method = :smtp
      ActionMailer::Base.smtp_settings = {}
      assert_raises(FamilyPlates::OutboundEmailNotConfiguredError) do
        FamilyPlates::OutboundEmail.validate!(environment: ActiveSupport::StringInquirer.new("production"))
      end
    ensure
      ActionMailer::Base.delivery_method = original_method
      ActionMailer::Base.smtp_settings = original_settings
    end
  end

  test "external identity providers and forward auth are disabled by default" do
    assert_equal false, FamilyPlates.config.google_auth_enabled?
    assert_equal false, FamilyPlates.config.apple_auth_enabled?
    assert_equal false, FamilyPlates.config.oidc_enabled?
    assert_equal false, FamilyPlates.config.forward_auth_enabled?
    assert_equal false, FamilyPlates.config.any_oauth_enabled?
    assert_equal ["127.0.0.1", "::1"], FamilyPlates.config.forward_auth_trusted_proxies
    assert_equal "Single Sign-On", FamilyPlates.config.oidc_display_name
  end

  test "enabling google auth requires credentials" do
    FamilyPlates.config.google_auth_enabled = true
    assert_not FamilyPlates.config.google_auth_enabled?

    FamilyPlates.config.google_client_id = "cid"
    FamilyPlates.config.google_client_secret = "csecret"
    assert FamilyPlates.config.google_auth_enabled?
    assert FamilyPlates.config.any_oauth_enabled?
  end

  test "enabling oidc requires client id, secret, and issuer or urls" do
    FamilyPlates.config.oidc_auth_enabled = true
    FamilyPlates.config.oidc_client_id = "oidc-id"
    FamilyPlates.config.oidc_client_secret = "oidc-secret"
    assert_not FamilyPlates.config.oidc_enabled?

    FamilyPlates.config.oidc_issuer = "https://auth.example.com"
    assert FamilyPlates.config.oidc_enabled?
    assert FamilyPlates.config.any_oauth_enabled?
  end

  test "reset! restores all external auth configs to nil/defaults" do
    FamilyPlates.config.google_auth_enabled = true
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.oidc_display_name = "Authentik"

    FamilyPlates.config.reset!

    assert_not FamilyPlates.config.google_auth_enabled?
    assert_not FamilyPlates.config.forward_auth_enabled?
    assert_equal "Single Sign-On", FamilyPlates.config.oidc_display_name
  end
end
