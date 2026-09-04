require "test_helper"

class OptInLoginAndIdempotentOnboardingTest < ActionDispatch::IntegrationTest
  setup do
    FamilyPlates.config.reset!
    @household = households(:one)
    @admin = family_members(:one)
    @member = family_members(:two)
  end

  teardown do
    FamilyPlates.config.reset!
  end

  test "appliance mode with REQUIRE_LOGIN=false allows one-tap profile selection without password" do
    assert_equal false, FamilyPlates.config.require_login

    get select_profile_path
    assert_response :success

    post set_profile_path(@member)
    assert_redirected_to root_url
    assert signed_in_as?(@member)
  end

  test "REQUIRE_LOGIN=true redirects strangers to sign in" do
    # Link admin to user with password so REQUIRE_LOGIN can be enabled
    admin_user = User.create!(email: "admin@example.com", password: "password123")
    @admin.update!(user: admin_user)
    FamilyPlates.config.require_login = true

    get root_path
    assert_redirected_to new_session_path
    assert_equal "Please sign in to continue.", flash[:alert]

    get select_profile_path
    assert_redirected_to new_session_path
    assert_equal "Please sign in to select a profile.", flash[:alert]
  end

  test "REQUIRE_LOGIN=true preserves one-tap profile switching once device session is established" do
    admin_user = User.create!(email: "admin@example.com", password: "password123")
    @admin.update!(user: admin_user)
    FamilyPlates.config.require_login = true

    post session_path, params: { email: admin_user.email, password: "password123" }
    assert_redirected_to root_url

    # Signed in as user on this device -> picker is now accessible
    get select_profile_path
    assert_response :success

    # Switching to a non-admin profile is still one tap (no PIN)
    post set_profile_path(@member)
    assert_redirected_to root_url
    assert signed_in_as?(@member)
  end

  test "onboarding sets onboarded_at on completion and blocks re-entry per household" do
    Household.destroy_all
    fresh_household = Household.create!(name: "Fresh Household")
    fresh_admin = fresh_household.family_members.create!(
      name: "Fresh Admin", role: "admin", pin: "1234", avatar_color: "#3B82F6", avatar_icon: "chef-hat"
    )
    fresh_household.update_columns(onboarded_at: nil)
    assert_not fresh_household.onboarded?

    # Sign in as admin to reach complete step
    sign_in_as(fresh_admin)

    get onboarding_complete_path
    assert_response :success
    assert fresh_household.reload.onboarded?

    # Attempting to re-enter onboarding is rejected because household is onboarded
    get onboarding_family_path
    assert_redirected_to root_path
    assert_equal "Your family kitchen is already set up.", flash[:alert]
  end
end
