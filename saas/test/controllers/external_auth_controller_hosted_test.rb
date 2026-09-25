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
          pin: "4826"
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
