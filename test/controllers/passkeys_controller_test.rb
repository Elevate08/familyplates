# frozen_string_literal: true

require "test_helper"

class PasskeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "passkey_test@example.com", password: "password123")
    @household = households(:one)
    @admin = family_members(:one)
    @admin.update!(user: @user)
  end

  test "index redirects when unauthenticated" do
    get passkeys_path
    assert_redirected_to new_session_path
    assert_equal "Please sign in to manage passkeys.", flash[:alert]
  end

  test "index renders passkeys list for signed-in user" do
    sign_in_user
    @user.passkeys.create!(external_id: "ext-1", public_key: "pk-1", nickname: "Work YubiKey")

    get passkeys_path
    assert_response :success
    assert_select "h3", text: /Work YubiKey/
  end

  # @card-19.3
  test "index blocks kiosk sessions" do
    sign_in_user
    @user.sessions.last.update_columns(kind: "kiosk")

    get passkeys_path
    assert_redirected_to root_path
    assert_equal "Kiosk devices cannot manage passkeys.", flash[:alert]
  end

  test "registration_options returns challenge and user details" do
    sign_in_user

    post registration_options_passkeys_path
    assert_response :success
    json = response.parsed_body
    assert json["challenge"].present?
    assert json["user"].present?
    assert_equal @user.email, json["user"]["name"]
  end

  test "authentication_options is open to strangers and sets challenge" do
    post authentication_options_passkeys_path
    assert_response :success
    json = response.parsed_body
    assert json["challenge"].present?
  end

  # @card-19.4
  test "destroy removes the passkey" do
    sign_in_user
    passkey = @user.passkeys.create!(external_id: "ext-to-remove", public_key: "pk-1", nickname: "Old Phone")

    assert_difference -> { @user.passkeys.count } => -1 do
      delete passkey_path(passkey)
    end

    assert_redirected_to passkeys_path
    assert_equal "Passkey removed.", flash[:notice]
  end

  # FP-APPSEC-005
  test "production relying party uses only the configured public origin" do
    old = ENV["APP_HOST"]
    ENV["APP_HOST"] = "plates.example.org"
    forged = ActionDispatch::TestRequest.create("HTTP_ORIGIN" => "https://evil.example.net", "HTTP_HOST" => "evil.example.net")

    rp_id, origins = PasskeysController.relying_party_settings(forged, environment: ActiveSupport::StringInquirer.new("production"))

    assert_equal "plates.example.org", rp_id
    assert_equal [ "https://plates.example.org" ], origins.map { |o| o.sub("http://", "https://") }.uniq
    assert_not_includes origins.join, "evil.example.net"
    assert_not_includes origins.join, "localhost"
    assert_not_includes origins.join, "example.com"
  ensure
    old ? ENV["APP_HOST"] = old : ENV.delete("APP_HOST")
  end

  # A LAN appliance runs without APP_HOST (docs/getting-started.md). Its
  # passkeys keep working on the host it is reached by, but the Origin
  # header, which a page controls, is never trusted.
  test "a production appliance without APP_HOST uses the request host, never the Origin header" do
    old = ENV.delete("APP_HOST")
    lan = ActionDispatch::TestRequest.create("HTTP_ORIGIN" => "https://evil.example.net", "HTTP_HOST" => "kitchen.lan:3000")
    rp_id, origins = PasskeysController.relying_party_settings(lan, environment: ActiveSupport::StringInquirer.new("production"))

    assert_equal "kitchen.lan", rp_id
    assert_equal [ "http://kitchen.lan:3000", "https://kitchen.lan:3000" ], origins.sort
    assert_not_includes origins.join, "evil.example.net"
  ensure
    ENV["APP_HOST"] = old if old
  end

  test "hosted production without APP_HOST still has no relying party" do
    skip "needs the hosted bundle" unless FamilyPlates.saas?
    old = ENV.delete("APP_HOST")
    FamilyPlates.config.mode = "hosted"
    rp_id, origins = PasskeysController.relying_party_settings(ActionDispatch::TestRequest.create,
      environment: ActiveSupport::StringInquirer.new("production"))
    assert_nil rp_id
    assert_empty origins
  ensure
    FamilyPlates.config.reset!
    ENV["APP_HOST"] = old if old
  end

  # A proxy that terminates TLS often leaves ASSUME_SSL unset; the browser's
  # origin is still https. Both schemes are allowed for the configured host
  # only, so a forged host still gains nothing.
  test "an appliance with APP_HOST and no SSL setting accepts either scheme for that host only" do
    old = ENV["APP_HOST"]
    ENV["APP_HOST"] = "plates.example.org"
    assume, force = Rails.application.config.assume_ssl, Rails.application.config.force_ssl
    Rails.application.config.assume_ssl = false
    Rails.application.config.force_ssl = false

    _rp, origins = PasskeysController.relying_party_settings(nil, environment: ActiveSupport::StringInquirer.new("production"))
    assert_equal [ "http://plates.example.org", "https://plates.example.org" ], origins.sort
  ensure
    Rails.application.config.assume_ssl = assume
    Rails.application.config.force_ssl = force
    old ? ENV["APP_HOST"] = old : ENV.delete("APP_HOST")
  end

  # With ASSUME_SSL or FORCE_SSL the app knows it is served over https.
  test "an appliance behind an HTTPS proxy expects an https origin" do
    old = ENV["APP_HOST"]
    ENV["APP_HOST"] = "plates.example.org"
    assume, force = Rails.application.config.assume_ssl, Rails.application.config.force_ssl
    Rails.application.config.assume_ssl = true
    Rails.application.config.force_ssl = false

    _rp, origins = PasskeysController.relying_party_settings(nil, environment: ActiveSupport::StringInquirer.new("production"))
    assert_equal [ "https://plates.example.org" ], origins
  ensure
    Rails.application.config.assume_ssl = assume
    Rails.application.config.force_ssl = force
    old ? ENV["APP_HOST"] = old : ENV.delete("APP_HOST")
  end

  test "non-production still accepts local origins" do
    _rp, origins = PasskeysController.relying_party_settings(nil, environment: ActiveSupport::StringInquirer.new("test"))
    assert_includes origins, "http://localhost:3000"
  end

  # FP-APPSEC-005: the relying party must come from APP_HOST, not the Host header.
  test "registration options in production ignore a forged host" do
    sign_in_user
    old = ENV["APP_HOST"]
    ENV["APP_HOST"] = "plates.example.org"
    production = ActiveSupport::EnvironmentInquirer.new("production")
    original = Rails.method(:env)
    Rails.define_singleton_method(:env) { production }

    begin
      post registration_options_passkeys_path, headers: { "Host" => "evil.example.net", "Origin" => "https://evil.example.net" }
    ensure
      Rails.define_singleton_method(:env, original)
      old ? ENV["APP_HOST"] = old : ENV.delete("APP_HOST")
    end

    assert_not_includes response.body, "evil.example.net"
    assert response.status == 503 || response.body.include?("plates.example.org"), "got #{response.status}"
  end

  private

  def sign_in_user
    post session_path, params: { email: @user.email, password: "password123" }
    assert_redirected_to root_url
  end
end
