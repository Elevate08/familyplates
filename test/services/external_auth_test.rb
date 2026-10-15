require "test_helper"

class ExternalAuthTest < ActiveSupport::TestCase
  setup do
    FamilyPlates.config.reset!
    ExternalAuth::Oidc.reset_discovery!
    [ ExternalAuth::Google, ExternalAuth::Oidc ].each(&:reset_jwks_cache!)
  end

  teardown do
    FamilyPlates.config.reset!
    ExternalAuth::Oidc.reset_discovery!
    [ ExternalAuth::Google, ExternalAuth::Oidc ].each(&:reset_jwks_cache!)
  end

  # @card-20.1
  test "providers are disabled by default" do
    assert_not ExternalAuth::Google.enabled?
    assert_not ExternalAuth::Oidc.enabled?
    assert_empty ExternalAuth.enabled_providers
  end

  test "provider_for resolves correct provider class" do
    assert_equal ExternalAuth::Google, ExternalAuth.provider_for("google")
    assert_nil ExternalAuth.provider_for("apple")
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

  # @card-20.8
  test "OIDC authorization URL uses configured auth URL and scope" do
    FamilyPlates.config.oidc_auth_enabled = true
    FamilyPlates.config.oidc_client_id = "familyplates-sso"
    FamilyPlates.config.oidc_client_secret = "sso-secret"
    FamilyPlates.config.oidc_issuer = "https://auth.example.com"
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

  test "stale Apple environment does not enable any provider" do
    old = ENV.to_h.slice("AUTH_APPLE_ENABLED", "APPLE_CLIENT_ID", "APPLE_CLIENT_SECRET")
    ENV["AUTH_APPLE_ENABLED"] = "true"
    ENV["APPLE_CLIENT_ID"] = "com.example.stale"
    ENV["APPLE_CLIENT_SECRET"] = "stale"
    assert_empty ExternalAuth.enabled_providers
    assert_not FamilyPlates.config.any_oauth_enabled?
  ensure
    %w[AUTH_APPLE_ENABLED APPLE_CLIENT_ID APPLE_CLIENT_SECRET].each { |k| old.key?(k) ? ENV[k] = old[k] : ENV.delete(k) }
  end

  GOOGLE_ISS = "https://accounts.google.com"

  def build_key
    @rsa = OpenSSL::PKey::RSA.generate(2048)
    jwk = JWT::JWK.new(@rsa, kid: "test-kid").export
    @jwks = { "keys" => [ jwk.transform_keys(&:to_s) ] }
  end

  def id_token(key: @rsa, **overrides)
    payload = {
      "iss" => GOOGLE_ISS, "aud" => "google-client", "sub" => "g-1",
      "email" => "chef@example.com", "email_verified" => true, "nonce" => "n-1",
      "exp" => 1.hour.from_now.to_i
    }.merge(overrides.transform_keys(&:to_s))
    JWT.encode(payload, key, "RS256", { kid: "test-kid" })
  end

  def with_jwks(klass)
    singleton = klass.singleton_class
    original = singleton.instance_method(:jwks)
    jwks = @jwks
    singleton.define_method(:jwks) { jwks }
    klass.reset_jwks_cache!
    yield
  ensure
    singleton.define_method(:jwks, original)
    klass.reset_jwks_cache!
  end

  test "Google id_token fallback verifies signature, iss, aud, exp and nonce" do
    build_key
    FamilyPlates.config.google_client_id = "google-client"
    with_jwks(ExternalAuth::Google) do
      info = ExternalAuth::Google.fetch_userinfo(nil, id_token, nonce: "n-1")
      assert_equal "g-1", info["sub"]
      assert_equal true, info["email_verified"]

      other = OpenSSL::PKey::RSA.generate(2048)
      bad = {
        "alg=none" => JWT.encode({ "iss" => GOOGLE_ISS, "aud" => "google-client", "nonce" => "n-1", "exp" => 1.hour.from_now.to_i }, nil, "none"),
        "wrong key" => id_token(key: other),
        "wrong aud" => id_token(aud: "someone-else"),
        "wrong iss" => id_token(iss: "https://evil.example.com"),
        "expired" => id_token(exp: 1.hour.ago.to_i)
      }
      bad.each do |label, token|
        assert_raises(JWT::DecodeError, label) { ExternalAuth::Google.fetch_userinfo(nil, token, nonce: "n-1") }
      end
      assert_raises(JWT::DecodeError) { ExternalAuth::Google.fetch_userinfo(nil, id_token, nonce: "other") }
      assert_raises(JWT::DecodeError) { ExternalAuth::Google.fetch_userinfo(nil, id_token, nonce: nil) }
    end
  end

  test "OIDC id_token fallback verifies against the configured issuer and client" do
    build_key
    FamilyPlates.config.oidc_issuer = "https://auth.example.com"
    FamilyPlates.config.oidc_client_id = "google-client"
    FamilyPlates.config.oidc_userinfo_url = nil
    original_discovery = ExternalAuth::Oidc.method(:discovery_endpoint)
    ExternalAuth::Oidc.define_singleton_method(:discovery_endpoint) { |_k| nil }
    with_jwks(ExternalAuth::Oidc) do
      info = ExternalAuth::Oidc.fetch_userinfo(nil, id_token(iss: "https://auth.example.com"), nonce: "n-1")
      assert_equal "g-1", info["sub"]

      assert_raises(JWT::DecodeError) { ExternalAuth::Oidc.fetch_userinfo(nil, id_token(iss: GOOGLE_ISS), nonce: "n-1") }
      assert_raises(JWT::DecodeError) { ExternalAuth::Oidc.fetch_userinfo(nil, id_token(iss: "https://auth.example.com", aud: "x"), nonce: "n-1") }
      assert_raises(JWT::DecodeError) { ExternalAuth::Oidc.fetch_userinfo(nil, id_token(iss: "https://auth.example.com", exp: 1.hour.ago.to_i), nonce: "n-1") }
      assert_raises(JWT::DecodeError) { ExternalAuth::Oidc.fetch_userinfo(nil, id_token(iss: "https://auth.example.com"), nonce: "bad") }
      assert_raises(JWT::DecodeError) { ExternalAuth::Oidc.fetch_userinfo(nil, id_token(key: OpenSSL::PKey::RSA.generate(2048), iss: "https://auth.example.com"), nonce: "n-1") }
    end
  ensure
    ExternalAuth::Oidc.define_singleton_method(:discovery_endpoint, original_discovery) if original_discovery
  end

  # Answers every HTTP request (the userinfo endpoint here) with `json`.
  def with_http_answer(json)
    res = Net::HTTPOK.new("1.1", "200", "OK")
    res.instance_variable_set(:@read, true)
    res.instance_variable_set(:@body, json.to_json)
    original = Net::HTTP.method(:start)
    Net::HTTP.define_singleton_method(:start) { |*, **| res }
    yield
  ensure
    Net::HTTP.define_singleton_method(:start, original)
  end

  test "a working userinfo endpoint does not skip the id_token and nonce checks" do
    build_key
    FamilyPlates.config.google_client_id = "google-client"
    with_jwks(ExternalAuth::Google) do
      with_http_answer("sub" => "g-1", "email" => "chef@example.com", "email_verified" => true, "name" => "Chef") do
        info = ExternalAuth::Google.fetch_userinfo("access", id_token, nonce: "n-1")
        assert_equal [ "g-1", "Chef" ], info.values_at("sub", "name")

        assert_raises(JWT::DecodeError) { ExternalAuth::Google.fetch_userinfo("access", id_token, nonce: "replayed") }
        assert_raises(JWT::DecodeError) { ExternalAuth::Google.fetch_userinfo("access", id_token(key: OpenSSL::PKey::RSA.generate(2048)), nonce: "n-1") }
      end
    end
  end

  test "userinfo for a different subject, or no id_token at all, is refused" do
    build_key
    FamilyPlates.config.google_client_id = "google-client"
    with_jwks(ExternalAuth::Google) do
      with_http_answer("sub" => "someone-else", "email" => "victim@example.com", "email_verified" => true) do
        assert_raises(RuntimeError) { ExternalAuth::Google.fetch_userinfo("access", id_token, nonce: "n-1") }
        assert_raises(RuntimeError) { ExternalAuth::Google.fetch_userinfo("access", nil, nonce: "n-1") }
      end
    end
  end

  # An appliance's own identity provider may leave email_verified out; it was
  # configured by the appliance owner, so that is not a refusal. An explicit
  # false still is, and the hosted service requires the claim.
  test "OIDC email_verified: missing counts as verified on an appliance only; false never does" do
    claims = ->(extra) { { "sub" => "o-1", "email" => "cook@example.com" }.merge(extra) }
    assert_equal true, ExternalAuth::Oidc.email_verified_claim(claims.call({}))
    assert_equal false, ExternalAuth::Oidc.email_verified_claim(claims.call("email_verified" => false))
    assert_equal true, ExternalAuth::Oidc.email_verified_claim(claims.call("email_verified" => "true"))

    if FamilyPlates.saas?
      FamilyPlates.config.mode = "hosted"
      assert_nil ExternalAuth::Oidc.email_verified_claim(claims.call({}))
    end
  ensure
    FamilyPlates.config.reset!
  end

  test "Google id_tokens are accepted with either issuer form Google documents" do
    build_key
    FamilyPlates.config.google_client_id = "google-client"
    with_jwks(ExternalAuth::Google) do
      assert_equal "g-1", ExternalAuth::Google.fetch_userinfo(nil, id_token(iss: "accounts.google.com"), nonce: "n-1")["sub"]
      assert_equal "g-1", ExternalAuth::Google.fetch_userinfo(nil, id_token(iss: "https://accounts.google.com"), nonce: "n-1")["sub"]
      assert_raises(JWT::DecodeError) { ExternalAuth::Google.fetch_userinfo(nil, id_token(iss: "https://evil.example.com"), nonce: "n-1") }
    end
  end

  # Authentik publishes its issuer with a trailing slash; operators often
  # leave it off. The issuer the provider itself publishes is the one used.
  test "OIDC accepts the issuer the provider publishes, with or without a trailing slash" do
    build_key
    FamilyPlates.config.oidc_issuer = "https://auth.example.com/application/o/familyplates"
    FamilyPlates.config.oidc_client_id = "google-client"
    published = "https://auth.example.com/application/o/familyplates/"
    original_discovery = ExternalAuth::Oidc.method(:discovery_endpoint)
    ExternalAuth::Oidc.define_singleton_method(:discovery_endpoint) { |key| key == "issuer" ? published : nil }
    with_jwks(ExternalAuth::Oidc) do
      assert_equal "g-1", ExternalAuth::Oidc.fetch_userinfo(nil, id_token(iss: published), nonce: "n-1")["sub"]
      assert_equal "g-1", ExternalAuth::Oidc.fetch_userinfo(nil, id_token(iss: published.chomp("/")), nonce: "n-1")["sub"]
      assert_raises(JWT::DecodeError) { ExternalAuth::Oidc.fetch_userinfo(nil, id_token(iss: "https://auth.example.com/other"), nonce: "n-1") }
    end
  ensure
    ExternalAuth::Oidc.define_singleton_method(:discovery_endpoint, original_discovery) if original_discovery
  end

  test "OIDC needs an issuer to be enabled, and takes its signing keys from OIDC_JWKS_URL when there is no discovery" do
    config = FamilyPlates.config
    config.oidc_auth_enabled = true
    config.oidc_client_id = "c"
    config.oidc_client_secret = "s"
    config.oidc_auth_url = "https://auth.example.com/authorize"
    config.oidc_token_url = "https://auth.example.com/token"
    assert_not config.oidc_enabled?, "without an issuer no id_token can be checked"

    config.oidc_issuer = "https://auth.example.com"
    assert config.oidc_enabled?

    ENV["OIDC_JWKS_URL"] = "https://auth.example.com/keys"
    original_discovery = ExternalAuth::Oidc.method(:discovery_endpoint)
    ExternalAuth::Oidc.define_singleton_method(:discovery_endpoint) { |_key| nil }
    requested = nil
    with_http_answer("keys" => []) do
      original = Net::HTTP::Get.method(:new)
      Net::HTTP::Get.define_singleton_method(:new) { |uri, *rest| requested = uri.to_s; original.call(uri, *rest) }
      ExternalAuth::Oidc.jwks
    ensure
      Net::HTTP::Get.define_singleton_method(:new, original)
    end
    assert_equal "https://auth.example.com/keys", requested
  ensure
    ENV.delete("OIDC_JWKS_URL")
    ExternalAuth::Oidc.define_singleton_method(:discovery_endpoint, original_discovery) if original_discovery
  end

  test "signing keys are fetched once and refetched only for an unknown key" do
    build_key
    FamilyPlates.config.google_client_id = "google-client"
    fetches = 0
    jwks = @jwks
    singleton = ExternalAuth::Google.singleton_class
    original = singleton.instance_method(:jwks)
    singleton.define_method(:jwks) { fetches += 1; jwks }
    ExternalAuth::Google.reset_jwks_cache!

    2.times { ExternalAuth::Google.fetch_userinfo(nil, id_token, nonce: "n-1") }
    assert_equal 1, fetches

    rotated = OpenSSL::PKey::RSA.generate(2048)
    jwks = { "keys" => [ JWT::JWK.new(rotated, kid: "new-kid").export.transform_keys(&:to_s) ] }
    token = JWT.encode({ "iss" => GOOGLE_ISS, "aud" => "google-client", "sub" => "g-1", "nonce" => "n-1", "exp" => 1.hour.from_now.to_i },
      rotated, "RS256", { kid: "new-kid" })
    assert_equal "g-1", ExternalAuth::Google.fetch_userinfo(nil, token, nonce: "n-1")["sub"]
    assert_equal 2, fetches
  ensure
    singleton.define_method(:jwks, original)
    ExternalAuth::Google.reset_jwks_cache!
  end

  test "token endpoint failures raise with the status code only" do
    FamilyPlates.config.google_client_id = "google-client"
    FamilyPlates.config.google_client_secret = "s"
    res = Net::HTTPBadRequest.new("1.1", "400", "Bad")
    res.instance_variable_set(:@read, true)
    res.instance_variable_set(:@body, "secret-body-text")
    original = Net::HTTP.method(:post_form)
    Net::HTTP.define_singleton_method(:post_form) { |*_a| res }
    error = assert_raises(RuntimeError) { ExternalAuth::Google.verify_and_exchange(code: "c", redirect_uri: "http://x") }
    assert_includes error.message, "400"
    assert_not_includes error.message, "secret-body-text"
  ensure
    Net::HTTP.define_singleton_method(:post_form, original)
  end
end
