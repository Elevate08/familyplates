require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get new_registration_url
    assert_response :success
  end

  test "should create household, user, and initial family member" do
    assert_difference -> { Household.count } => 1, -> { User.count } => 1, -> { FamilyMember.count } => 1 do
      post registration_url, params: {
        household: { name: "New Family" },
        family_member_name: "Captain Chef",
        user: { email_address: "newbie@example.com", password: "password123", password_confirmation: "password123" }
      }
    end

    assert_redirected_to onboarding_recipes_url
    assert_equal "Captain Chef", FamilyMember.last.name
  end
end
