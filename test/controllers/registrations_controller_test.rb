require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "should get new when no household exists" do
    Household.destroy_all
    get new_registration_url
    assert_response :success
  end

  test "should redirect new when household already exists" do
    get new_registration_url
    assert_redirected_to new_session_url
    assert_equal "This kitchen is already configured. Please sign in.", flash[:alert]
  end

  test "should redirect new when authenticated and household exists" do
    sign_in_as(users(:one))
    get new_registration_url
    assert_redirected_to root_url
    assert_equal "Your family kitchen is already set up.", flash[:alert]
  end

  test "should create household, user, and initial family member when no household exists" do
    Household.destroy_all
    assert_difference -> { Household.count } => 1, -> { User.count } => 1, -> { FamilyMember.count } => 1 do
      post registration_url, params: {
        household: { name: "New Family" },
        family_member_name: "Captain Chef",
        family_member_pin: "4321",
        user: { email_address: "newbie@example.com", password: "password123", password_confirmation: "password123" }
      }
    end

    assert_redirected_to onboarding_recipes_url
    admin = FamilyMember.last
    assert_equal "Captain Chef", admin.name
    assert_equal "4321", admin.pin
    assert admin.requires_pin?
  end

  test "should reject registration when household already exists" do
    assert_no_difference [ "Household.count", "User.count", "FamilyMember.count" ] do
      post registration_url, params: {
        household: { name: "Another Family" },
        family_member_name: "Intruder",
        user: { email_address: "intruder@example.com", password: "password123", password_confirmation: "password123" }
      }
    end

    assert_redirected_to new_session_url
  end
end
