# frozen_string_literal: true

require "test_helper"
require "webauthn/fake_client"

class PasskeyAuthenticationTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "passkey_hero@example.com", password: "password123")
    @household = households(:one)
    @admin = family_members(:one)
    @admin.update!(user: @user)
    @origin = "http://www.example.com"
    @client = WebAuthn::FakeClient.new(@origin)
  end

  test "full WebAuthn passkey registration and email-free authentication flow" do
    # 1. User signs in on their device
    post session_path, params: { email: @user.email, password: "password123" }
    assert_redirected_to root_url

    # 2. User requests registration options
    post registration_options_passkeys_path
    assert_response :success
    options = response.parsed_body
    challenge = options["challenge"]
    assert challenge.present?

    # 3. Client authenticator creates credential
    credential = @client.create(challenge: challenge)

    # 4. User saves passkey
    assert_difference -> { @user.passkeys.count } => 1 do
      post passkeys_path, params: {
        credential: credential,
        nickname: "MacBook Touch ID"
      }
    end
    assert_redirected_to passkeys_path
    passkey = @user.passkeys.last
    assert_equal "MacBook Touch ID", passkey.nickname
    assert_equal credential["id"], passkey.external_id
    assert @user.identities.exists?(provider: "passkey", uid: credential["id"])

    # 5. User signs out
    delete session_path
    assert cookies[:session_token].blank?

    # 6. Start passkey authentication (email-free, discoverable passkey)
    post authentication_options_passkeys_path
    assert_response :success
    auth_options = response.parsed_body
    auth_challenge = auth_options["challenge"]
    assert auth_challenge.present?

    # 7. Authenticator generates assertion
    assertion = @client.get(challenge: auth_challenge)

    # 8. Post assertion to callback
    post callback_passkeys_path, params: { credential: assertion }
    assert_response :success
    result = response.parsed_body
    assert result["ok"]
    assert_equal root_url, result["redirect_url"]

    # 9. Session is active and sign_count / last_used_at updated
    assert cookies[:session_token].present?
    assert passkey.reload.last_used_at.present?

    # 10. Access protected page with newly established passkey session
    get select_profile_path
    assert_response :success
  end

  test "rejects passkey authentication with unknown credential" do
    # Authenticator has created a credential for another site/user
    dummy_challenge = WebAuthn.configuration.encoder.encode(SecureRandom.random_bytes(32))
    @client.create(challenge: dummy_challenge)

    post authentication_options_passkeys_path
    auth_options = response.parsed_body
    auth_challenge = auth_options["challenge"]

    assertion = @client.get(challenge: auth_challenge)

    post callback_passkeys_path, params: { credential: assertion }
    assert_response :unprocessable_entity
    assert_includes response.parsed_body["error"], "Passkey not recognized"
  end

  test "rejects passkey callback when challenge session has expired" do
    post callback_passkeys_path, params: { credential: { id: "test" } }
    assert_response :unprocessable_entity
    assert_includes response.parsed_body["error"], "expired"
  end
end
