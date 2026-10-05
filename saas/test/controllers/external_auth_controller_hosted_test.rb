require "test_helper"

class ExternalAuthControllerHostedTest < ActionDispatch::IntegrationTest
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

  test "hosted mode authenticated user creates household directly without second email verification" do
    FamilyPlates.config.mode = "hosted"
    user = User.create!(email: "verified@example.com")
    session_record = user.sessions.create!(token: "sess-v1", last_active_at: Time.current)
    jar = ActionDispatch::Cookies::CookieJar.build(ActionDispatch::TestRequest.create, {})
    jar.signed[:session_token] = session_record.token
    cookies[:session_token] = jar[:session_token]

    assert_no_emails do
      assert_difference -> { Household.count } => 1, -> { FamilyMember.count } => 1 do
        post signup_path, params: {
          household_name: "The Verifieds",
          organizer_name: "Vee",
          email: "verified@example.com",
          pin: "4826",
          **terms_assent_params
        }
      end
    end

    assert_redirected_to onboarding_recipes_path
    assert_equal "Welcome to The Verifieds, Vee! Let's set up your recipes.", flash[:notice]
  end

  test "hosted mode OAuth sign-in without household redirects to signup without alert errors" do
    FamilyPlates.config.mode = "hosted"
    FamilyPlates.config.google_auth_enabled = true
    FamilyPlates.config.google_client_id = "test-client-id"
    FamilyPlates.config.google_client_secret = "test-secret"

    post auth_request_path(provider: :google)
    valid_state = session[:oauth_state]

    fake_auth = {
      provider: "google",
      uid: "google-fresh-user-1",
      email: "fresh@example.com",
      email_verified: true,
      name: "Fresh Google User"
    }

    with_stub(ExternalAuth::Google, :verify_and_exchange, fake_auth) do
      get auth_callback_path(provider: :google), params: { code: "oauth-code-123", state: valid_state }

      assert_redirected_to root_url
      assert_equal "Signed in successfully with Google.", flash[:notice]

      follow_redirect!

      assert_redirected_to new_signup_path
      assert_nil flash[:alert]

      follow_redirect!
      assert_response :success
      assert_select "h1", text: /Create Your Family Kitchen/i
      assert_nil flash[:alert]
    end
  end

  test "hosted mode OAuth callback with email_verified false does not sign in" do
    assert_hosted_oauth_rejected(email_verified: false)
  end

  test "hosted mode OAuth callback without email_verified is rejected" do
    assert_hosted_oauth_rejected
  end

  test "hosted mode OAuth callback does not link an existing user when email is unverified" do
    User.create!(email: "victim-oauth@example.com", password: "password123")
    FamilyPlates.config.mode = "hosted"
    FamilyPlates.config.google_auth_enabled = true
    FamilyPlates.config.google_client_id = "test-client-id"
    FamilyPlates.config.google_client_secret = "test-secret"

    post auth_request_path(provider: :google)
    valid_state = session[:oauth_state]

    fake_auth = {
      provider: "google",
      uid: "google-unverified-existing",
      email: "victim-oauth@example.com",
      email_verified: false,
      name: "Victim"
    }

    with_stub(ExternalAuth::Google, :verify_and_exchange, fake_auth) do
      assert_no_difference [ -> { Identity.count }, -> { Session.count }, -> { User.count } ] do
        get auth_callback_path(provider: :google), params: { code: "oauth-code-123", state: valid_state }
      end

      assert_redirected_to new_session_path
      assert_not cookies[:session_token].present?
      assert_nil Identity.find_by(provider: "google", uid: "google-unverified-existing")
      assert User.find_by(email: "victim-oauth@example.com").authenticate("password123")
    end
  end

  test "hosted mode OIDC callback does not sign in or link an existing user when email is unverified" do
    User.create!(email: "victim-oidc@example.com", password: "password123")
    FamilyPlates.config.mode = "hosted"
    FamilyPlates.config.oidc_auth_enabled = true
    FamilyPlates.config.oidc_client_id = "sso-client"
    FamilyPlates.config.oidc_client_secret = "sso-secret"
    FamilyPlates.config.oidc_auth_url = "https://auth.example.com/oauth2/authorize"
    FamilyPlates.config.oidc_token_url = "https://auth.example.com/oauth2/token"

    [ { email_verified: false }, {} ].each do |extra|
      post auth_request_path(provider: :oidc)
      fake = { provider: "oidc", uid: "oidc-unverified-existing", email: "victim-oidc@example.com", name: "V" }.merge(extra)
      with_stub(ExternalAuth::Oidc, :verify_and_exchange, fake) do
        assert_no_difference [ "Session.count", "Identity.count", "User.count" ] do
          get auth_callback_path(provider: :oidc), params: { code: "c", state: session[:oauth_state] }
        end
      end
      assert_redirected_to new_session_path
      assert_nil cookies[:session_token].presence
      assert_nil Identity.find_by(provider: "oidc", uid: "oidc-unverified-existing")
    end
  end

  private

  def assert_hosted_oauth_rejected(**extra)
    FamilyPlates.config.mode = "hosted"
    FamilyPlates.config.google_auth_enabled = true
    FamilyPlates.config.google_client_id = "test-client-id"
    FamilyPlates.config.google_client_secret = "test-secret"

    post auth_request_path(provider: :google)
    valid_state = session[:oauth_state]

    fake_auth = {
      provider: "google",
      uid: "google-unverified-1",
      email: "unverified@example.com",
      name: "Unverified User"
    }.merge(extra)

    with_stub(ExternalAuth::Google, :verify_and_exchange, fake_auth) do
      assert_no_difference [ "User.count", "Identity.count" ] do
        get auth_callback_path(provider: :google), params: { code: "oauth-code-123", state: valid_state }
      end

      assert_redirected_to new_session_path
      assert_not cookies[:session_token].present?
      assert_nil Identity.find_by(provider: "google", uid: "google-unverified-1")
      assert_nil User.find_by(email: "unverified@example.com")
    end
  end

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
