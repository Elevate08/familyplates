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

  test "hosted production refuses to start until SMTP_ADDRESS is set" do
    FamilyPlates.config.mode = "hosted"
    production = ActiveSupport::StringInquirer.new("production")

    with_smtp_env(nil) do
      error = assert_raises(FamilyPlates::OutboundEmailNotConfiguredError) do
        FamilyPlates::OutboundEmail.validate!(environment: production)
      end
      assert_match "SMTP_ADDRESS", error.message
    end

    with_smtp_env("SMTP_ADDRESS" => "smtp.example.com") do
      assert_nothing_raised do
        FamilyPlates::OutboundEmail.validate!(environment: production)
      end
    end
  end

  test "a LAN appliance starts without SMTP" do
    FamilyPlates.config.mode = "appliance"
    production = ActiveSupport::StringInquirer.new("production")

    with_smtp_env(nil) do
      assert_nothing_raised do
        FamilyPlates::OutboundEmail.validate!(environment: production)
      end
      assert_not FamilyPlates.hosted_host_missing?(environment: production)
    end
  end

  test "hosted production refuses to start without APP_HOST" do
    FamilyPlates.config.mode = "hosted"
    production = ActiveSupport::StringInquirer.new("production")

    with_smtp_env("APP_HOST" => nil) do
      assert FamilyPlates.hosted_host_missing?(environment: production)
    end

    with_smtp_env("APP_HOST" => "https://plates.example.com/kitchen") do
      assert_equal "plates.example.com", FamilyPlates.public_host
      assert_not FamilyPlates.hosted_host_missing?(environment: production)
    end
  end

  test "partial SMTP settings refuse to start" do
    FamilyPlates.config.mode = "appliance"
    production = ActiveSupport::StringInquirer.new("production")

    with_smtp_env("SMTP_USER_NAME" => "mailer", "SMTP_PASSWORD" => nil, "SMTP_ADDRESS" => nil) do
      assert_raises(FamilyPlates::OutboundEmailNotConfiguredError) do
        FamilyPlates::OutboundEmail.validate!(environment: production)
      end
    end

    with_smtp_env("SMTP_ADDRESS" => "smtp.example.com", "SMTP_USER_NAME" => "mailer", "SMTP_PASSWORD" => nil) do
      error = assert_raises(FamilyPlates::OutboundEmailNotConfiguredError) do
        FamilyPlates::OutboundEmail.validate!(environment: production)
      end
      assert_match "SMTP_PASSWORD", error.message
    end
  end

  test "external identity providers and forward auth are disabled by default" do
    assert_equal false, FamilyPlates.config.google_auth_enabled?
    assert_equal false, FamilyPlates.config.apple_auth_enabled?
    assert_equal false, FamilyPlates.config.oidc_enabled?
    assert_equal false, FamilyPlates.config.forward_auth_enabled?
    assert_equal false, FamilyPlates.config.any_oauth_enabled?
    assert_equal [ "127.0.0.1", "::1" ], FamilyPlates.config.forward_auth_trusted_proxies
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

  private

  def with_smtp_env(overrides)
    keys = FamilyPlates::OutboundEmail::SMTP_ENV_KEYS + %w[APP_HOST]
    original = keys.to_h { |key| [ key, ENV[key] ] }
    keys.each { |key| ENV.delete(key) }
    overrides&.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    yield
  ensure
    original.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end
end
