require "test_helper"

class SignupsExistingUserAuthTest < ActionDispatch::IntegrationTest
  ORIGINAL_PASSWORD = "original-password-123"

  setup do
    FamilyPlates.config.reset!
    @user = User.create!(email: "existing-owner@example.com", password: ORIGINAL_PASSWORD)
  end

  teardown do
    FamilyPlates.config.reset!
  end

  def sign_in_user(user, password = nil)
    post session_path, params: { email: user.email, password: password || (user == @user ? ORIGINAL_PASSWORD : "other-password-123") }
    assert_redirected_to root_url
  end

  def signup_params(overrides = {})
    {
      household_name: "Intruder Household",
      organizer_name: "Intruder",
      email: @user.email,
      pin: "4826"
    }.merge(overrides)
  end

  def assert_refused_without_session
    assert_response :unprocessable_entity
    assert_no_match(/already exists/i, flash[:alert].to_s)
    assert_match(/sign in/i, flash[:alert].to_s)
    assert_nil cookies[:session_token].presence
    assert_equal @user, User.find_by(email: "existing-owner@example.com")
    assert @user.reload.authenticate(ORIGINAL_PASSWORD), "original password must still work"
  end

  test "appliance mode refuses existing user with wrong password" do
    assert_no_difference [ -> { Household.count }, -> { FamilyMember.count }, -> { Session.count }, -> { User.count } ] do
      post signup_path, params: signup_params(password: "wrong-password")
    end

    assert_refused_without_session
  end

  test "appliance mode refuses existing user even with the correct password" do
    assert_no_difference [ -> { Household.count }, -> { FamilyMember.count }, -> { Session.count }, -> { User.count } ] do
      post signup_path, params: signup_params(password: ORIGINAL_PASSWORD)
    end

    assert_refused_without_session
  end

  test "appliance mode still provisions a new email without terms" do
    assert_difference -> { User.count } => 1, -> { Household.count } => 1, -> { Session.count } => 1 do
      post signup_path, params: signup_params(email: "brand-new@example.com", password: "new-pass-123")
    end

    assert_redirected_to onboarding_recipes_path
    assert cookies[:session_token].present?
    assert User.find_by(email: "brand-new@example.com").authenticate("new-pass-123")
  end

  test "appliance mode reuses the existing user when already signed in as them" do
    sign_in_user(@user)

    assert_difference -> { Household.count } => 1, -> { FamilyMember.count } => 1 do
      assert_no_difference -> { User.count } do
        post signup_path, params: signup_params(password: "ignored")
      end
    end

    assert_redirected_to onboarding_recipes_path
    assert_equal @user, FamilyMember.find_by!(name: "Intruder").user
    assert @user.reload.authenticate(ORIGINAL_PASSWORD)
  end

  test "appliance mode does not reuse a victim when a different user is signed in" do
    other = User.create!(email: "other-signed-in@example.com", password: "other-password-123")
    sign_in_user(other)
    victim_sessions = @user.sessions.count

    assert_no_difference [ -> { Household.count }, -> { FamilyMember.count } ] do
      post signup_path, params: signup_params(password: ORIGINAL_PASSWORD)
    end

    assert_response :unprocessable_entity
    assert_equal victim_sessions, @user.reload.sessions.count
    assert @user.authenticate(ORIGINAL_PASSWORD)
  end

  test "hosted mode does not sign in an existing user from an unauthenticated signup" do
    FamilyPlates.config.mode = "hosted"

    assert_no_difference [ -> { Household.count }, -> { Session.count } ] do
      post signup_path, params: signup_params(password: "wrong-password", accept_terms: "1")
    end

    assert_includes [ 302, 303, 422 ], response.status
    assert_nil cookies[:session_token].presence
    assert @user.reload.authenticate(ORIGINAL_PASSWORD)
  end
end
