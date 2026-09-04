require "test_helper"

class ExternalAuthTest < ActiveSupport::TestCase
  setup do
    FamilyPlates.config.reset!
    ExternalAuth::Oidc.reset_discovery!
  end

  teardown do
    FamilyPlates.config.reset!
    ExternalAuth::Oidc.reset_discovery!
  end

  test "providers are disabled by default" do
    assert_not ExternalAuth::Google.enabled?
    assert_not ExternalAuth::Apple.enabled?
    assert_not ExternalAuth::Oidc.enabled?
    assert_empty ExternalAuth.enabled_providers
  end

  test "provider_for resolves correct provider class" do
    assert_equal ExternalAuth::Google, ExternalAuth.provider_for("google")
    assert_equal ExternalAuth::Apple, ExternalAuth.provider_for("apple")
    assert_equal ExternalAuth::Oidc, ExternalAuth.provider_for("oidc")
    assert_nil ExternalAuth.provider_for("unsupported")
  end

  test "Google authorization URL includes client_id, state, and nonce" do
    FamilyPlates.config.google_auth_enabled = true
    FamilyPlates.config.google_client_id = "google-client-id.apps.googleusercontent.com"
    FamilyPlates.config.google_client_secret = "secret"

    url = ExternalAuth::Google.authorization_url(
      redirect_uri: "http://example.com/auth/google/callback",
      state: "state123",
      nonce: "nonce456"
    )

    uri = URI(url)
    params = Rack::Utils.parse_query(uri.query)

    assert_equal "accounts.google.com", uri.host
    assert_equal "google-client-id.apps.googleusercontent.com", params["client_id"]
    assert_equal "state123", params["state"]
    assert_equal "nonce456", params["nonce"]
    assert_equal "code", params["response_type"]
    assert_includes params["scope"], "openid"
  end

  test "Apple authorization URL includes client_id, form_post response mode" do
    FamilyPlates.config.apple_auth_enabled = true
    FamilyPlates.config.apple_client_id = "com.example.familyplates"
    FamilyPlates.config.apple_client_secret = "secret"

    url = ExternalAuth::Apple.authorization_url(
      redirect_uri: "http://example.com/auth/apple/callback",
      state: "state123",
      nonce: "nonce456"
    )

    uri = URI(url)
    params = Rack::Utils.parse_query(uri.query)

    assert_equal "appleid.apple.com", uri.host
    assert_equal "com.example.familyplates", params["client_id"]
    assert_equal "form_post", params["response_mode"]
    assert_equal "code id_token", params["response_type"]
    assert_equal "state123", params["state"]
  end

  test "OIDC authorization URL uses configured auth URL and scope" do
    FamilyPlates.config.oidc_auth_enabled = true
    FamilyPlates.config.oidc_client_id = "familyplates-sso"
    FamilyPlates.config.oidc_client_secret = "sso-secret"
    FamilyPlates.config.oidc_auth_url = "https://auth.example.com/application/o/authorize/"
    FamilyPlates.config.oidc_token_url = "https://auth.example.com/application/o/token/"

    url = ExternalAuth::Oidc.authorization_url(
      redirect_uri: "http://example.com/auth/oidc/callback",
      state: "state123",
      nonce: "nonce456"
    )

    uri = URI(url)
    params = Rack::Utils.parse_query(uri.query)

    assert_equal "auth.example.com", uri.host
    assert_equal "familyplates-sso", params["client_id"]
    assert_equal "state123", params["state"]
    assert_equal "openid profile email", params["scope"]
  end

  test "Apple verify_and_exchange decodes ID token and extracts user name" do
    payload = { "sub" => "apple-user-999", "email" => "apple@example.com" }
    id_token = JWT.encode(payload, nil, "none")

    result = ExternalAuth::Apple.verify_and_exchange(
      id_token: id_token,
      user_param: { "name" => { "firstName" => "Jane", "lastName" => "Chef" } }.to_json
    )

    assert_equal "apple", result[:provider]
    assert_equal "apple-user-999", result[:uid]
    assert_equal "apple@example.com", result[:email]
    assert_equal "Jane Chef", result[:name]
  end
end
