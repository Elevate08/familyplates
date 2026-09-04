require "test_helper"

class ExternalAuthControllerTest < ActionDispatch::IntegrationTest
  setup do
    FamilyPlates.config.reset!
    @user = User.create!(email: "chef@example.com", password: "password123")
    @household = households(:one)
    @admin = family_members(:one)
    @admin.update!(user: @user)
  end

  teardown do
    FamilyPlates.config.reset!
  end

  test "passthru redirects with alert when provider is disabled" do
    post auth_request_path(provider: :google)

    assert_redirected_to new_session_path
    assert_equal "Google authentication is not enabled.", flash[:alert]
  end

  test "passthru initiates authorization redirect and saves state in session" do
    FamilyPlates.config.google_auth_enabled = true
    FamilyPlates.config.google_client_id = "test-client-id"
    FamilyPlates.config.google_client_secret = "test-secret"

    post auth_request_path(provider: :google)

    assert_response :redirect
    assert_includes response.location, "accounts.google.com/o/oauth2/v2/auth"
    assert_includes response.location, "client_id=test-client-id"
    assert session[:oauth_state].present?
    assert_equal "google", session[:oauth_provider]
  end

  test "callback rejects request when provider returns error" do
    get auth_callback_path(provider: :google), params: { error: "access_denied", error_description: "The user denied access" }

    assert_redirected_to new_session_path
    assert_includes flash[:alert], "The user denied access"
  end

  test "callback rejects request when state does not match session (CSRF protection)" do
    get auth_callback_path(provider: :google), params: { code: "valid-code", state: "forged-state" }

    assert_redirected_to new_session_path
    assert_equal "Authentication failed: invalid state.", flash[:alert]
  end

  test "callback logs in and links identity to existing user matching email" do
    FamilyPlates.config.google_auth_enabled = true
    FamilyPlates.config.google_client_id = "test-client-id"
    FamilyPlates.config.google_client_secret = "test-secret"

    post auth_request_path(provider: :google)
    valid_state = session[:oauth_state]

    fake_auth = {
      provider: "google",
      uid: "google-sub-456",
      email: "chef@example.com",
      name: "Chef Jane"
    }

    with_stub(ExternalAuth::Google, :verify_and_exchange, fake_auth) do
      assert_no_difference -> { User.count } do
        assert_difference -> { Identity.count } => 1 do
          get auth_callback_path(provider: :google), params: { code: "oauth-code-123", state: valid_state }

          assert_redirected_to root_url
          assert cookies[:session_token].present?
          assert_equal "Signed in successfully with Google.", flash[:notice]
        end
      end
    end

    assert @user.identities.exists?(provider: "google", uid: "google-sub-456")
  end

  test "callback creates new user when email does not exist" do
    FamilyPlates.config.oidc_auth_enabled = true
    FamilyPlates.config.oidc_client_id = "sso-client"
    FamilyPlates.config.oidc_client_secret = "sso-secret"
    FamilyPlates.config.oidc_auth_url = "https://auth.example.com/oauth2/authorize"
    FamilyPlates.config.oidc_token_url = "https://auth.example.com/oauth2/token"

    post auth_request_path(provider: :oidc)
    valid_state = session[:oauth_state]

    fake_auth = {
      provider: "oidc",
      uid: "authentik-sub-789",
      email: "brandnew@example.com",
      name: "Brand New User"
    }

    with_stub(ExternalAuth::Oidc, :verify_and_exchange, fake_auth) do
      assert_difference -> { User.count } => 1, -> { Identity.count } => 1 do
        get auth_callback_path(provider: :oidc), params: { code: "sso-code", state: valid_state }

        assert_redirected_to root_url
        assert cookies[:session_token].present?
        assert_equal "Signed in successfully with Oidc.", flash[:notice]
      end
    end
  end

  test "Apple POST form_post callback authenticates without CSRF authenticity token" do
    FamilyPlates.config.apple_auth_enabled = true
    FamilyPlates.config.apple_client_id = "com.familyplates.app"
    FamilyPlates.config.apple_client_secret = "apple-secret"

    post auth_request_path(provider: :apple)
    valid_state = session[:oauth_state]

    fake_auth = {
      provider: "apple",
      uid: "apple-sub-abc",
      email: "appleuser@example.com",
      name: "Apple User"
    }

    with_stub(ExternalAuth::Apple, :verify_and_exchange, fake_auth) do
      post auth_callback_path(provider: :apple), params: { code: "apple-code", state: valid_state, id_token: "dummy-token" }

      assert_redirected_to root_url
      assert cookies[:session_token].present?
      assert_equal "Signed in successfully with Apple.", flash[:notice]
    end
  end

  test "connect mode links identity to currently logged in user" do
    sign_in_user

    FamilyPlates.config.google_auth_enabled = true
    FamilyPlates.config.google_client_id = "client"
    FamilyPlates.config.google_client_secret = "secret"

    post auth_request_path(provider: :google)
    valid_state = session[:oauth_state]

    fake_auth = {
      provider: "google",
      uid: "google-linked-id",
      email: "different-google-email@example.com",
      name: "Chef Jane"
    }

    with_stub(ExternalAuth::Google, :verify_and_exchange, fake_auth) do
      assert_no_difference -> { User.count } do
        assert_difference -> { Identity.count } => 1 do
          get auth_callback_path(provider: :google), params: { code: "code-xyz", state: valid_state }

          assert_redirected_to edit_preferences_path
          assert_equal "Successfully connected Google to your account!", flash[:notice]
        end
      end
    end

    assert @user.identities.exists?(provider: "google", uid: "google-linked-id")
  end

  test "destroy_identity allows disconnect when user has another sign-in method" do
    sign_in_user

    identity = @user.identities.create!(provider: "google", uid: "uid-to-delete")

    assert_difference -> { Identity.count } => -1 do
      delete auth_identity_path(identity)

      assert_redirected_to edit_preferences_path
      assert_equal "Disconnected Google account.", flash[:notice]
    end
  end

  test "destroy_identity prevents disconnect when it is the user's sole credential" do
    passwordless_user = User.create!(email: "only_google@example.com")
    identity = passwordless_user.identities.create!(provider: "google", uid: "google-sole-id")

    member = @household.family_members.second
    member.update!(user: passwordless_user)

    # Sign in as passwordless user
    session_record = passwordless_user.sessions.create!(token: "sess-pwless-1", last_active_at: Time.current)
    jar = ActionDispatch::Cookies::CookieJar.build(ActionDispatch::TestRequest.create, {})
    jar.signed[:session_token] = session_record.token
    cookies[:session_token] = jar[:session_token]
    jar.signed[:active_family_member_id] = member.id
    cookies[:active_family_member_id] = jar[:active_family_member_id]

    assert_no_difference -> { Identity.count } do
      delete auth_identity_path(identity)

      assert_redirected_to edit_preferences_path
      assert_includes flash[:alert], "Cannot disconnect this sign-in method"
    end
  end

  private

  def sign_in_user
    post session_path, params: { email: @user.email, password: "password123" }
    assert_redirected_to root_url
  end

  def with_stub(klass, method_name, return_value)
    singleton = klass.singleton_class
    original_method = singleton.instance_method(method_name)
    singleton.define_method(method_name) { |*args, **kwargs| return_value }
    yield
  ensure
    singleton.define_method(method_name, original_method)
  end
end
