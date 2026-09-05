require "test_helper"

class SignupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    FamilyPlates.config.reset!
  end

  teardown do
    FamilyPlates.config.reset!
  end

  test "new renders signup form" do
    get new_signup_path
    assert_response :success
    assert_select "h1", text: /Create Your Family Kitchen/i
  end

  test "create rejects missing parameters" do
    post signup_path, params: { household_name: "", organizer_name: "", email: "" }
    assert_response :unprocessable_entity
    assert_equal "Please provide your household name, your name, and a valid email address.", flash[:alert]
  end

  test "create rejects invalid email format" do
    post signup_path, params: { household_name: "The Bakers", organizer_name: "Baker", email: "not-an-email" }
    assert_response :unprocessable_entity
    assert_equal "Please enter a valid email address.", flash[:alert]
  end

  test "hosted mode create sends verification code and redirects to verify" do
    FamilyPlates.config.mode = "hosted"

    assert_enqueued_emails 1 do
      assert_difference -> { MagicCode.count } => 1 do
        post signup_path, params: {
          household_name: "The Bakers",
          organizer_name: "Bob Baker",
          email: "baker@example.com"
        }
      end
    end

    assert_redirected_to verify_signup_path
    assert_equal "baker@example.com", session[:pending_signup]["email"]
    assert_equal "The Bakers", session[:pending_signup]["household_name"]
  end

  test "hosted mode verify creates household, organizer member, user, and starts session" do
    FamilyPlates.config.mode = "hosted"

    # Step 1: Submit signup
    post signup_path, params: {
      household_name: "The Hosted Family",
      organizer_name: "Alice",
      email: "alice@example.com"
    }
    assert_redirected_to verify_signup_path

    magic_code = MagicCode.find_by!(email: "alice@example.com")

    # Step 2: Submit verification code
    assert_difference -> { Household.count } => 1, -> { User.count } => 1, -> { FamilyMember.count } => 1 do
      post verify_signup_path, params: { code: magic_code.code }
    end

    assert_redirected_to onboarding_recipes_path
    assert cookies[:session_token].present?
    assert cookies[:active_family_member_id].present?

    user = User.find_by!(email: "alice@example.com")
    household = Household.find_by!(name: "The Hosted Family")
    member = household.family_members.find_by!(name: "Alice")
    assert_equal "admin", member.role
    assert_equal user, member.user
    assert_not household.onboarded?
  end

  test "hosted mode verify rejects incorrect code" do
    FamilyPlates.config.mode = "hosted"

    post signup_path, params: {
      household_name: "The Hosted Family",
      organizer_name: "Alice",
      email: "alice@example.com"
    }

    assert_no_difference -> { Household.count } do
      post verify_signup_path, params: { code: "WRONG1" }
    end

    assert_response :unprocessable_entity
    assert_equal "Invalid or expired verification code.", flash[:alert]
  end

  test "appliance mode create provisions household and organizer immediately" do
    assert_difference -> { Household.count } => 1, -> { User.count } => 1, -> { FamilyMember.count } => 1 do
      post signup_path, params: {
        household_name: "Appliance Family",
        organizer_name: "Chef Head",
        email: "chefhead@example.com"
      }
    end

    assert_redirected_to onboarding_recipes_path
    assert cookies[:session_token].present?
    assert cookies[:active_family_member_id].present?
  end
end
