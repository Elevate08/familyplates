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

  test "create rejects a missing PIN" do
    assert_no_difference -> { Household.count } do
      post signup_path, params: {
        household_name: "The Bakers",
        organizer_name: "Baker",
        email: "baker@example.com",
        pin: ""
      }
    end

    assert_response :unprocessable_entity
    assert_equal "Please choose a 4-digit security PIN.", flash[:alert]
  end

  # @card-21.1
  test "hosted mode create sends verification code and redirects to verify" do
    FamilyPlates.config.mode = "hosted"

    assert_enqueued_emails 1 do
      assert_difference -> { MagicCode.count } => 1 do
        post signup_path, params: {
          household_name: "The Bakers",
          organizer_name: "Bob Baker",
          email: "baker@example.com",
          pin: "4826",
          **terms_assent_params
        }
      end
    end

    assert_redirected_to verify_signup_path
    assert_equal "baker@example.com", session[:pending_signup]["email"]
    assert_equal "The Bakers", session[:pending_signup]["household_name"]
  end

  # @card-21.1
  test "hosted mode verify creates household, organizer member, user, and starts session" do
    FamilyPlates.config.mode = "hosted"

    # Step 1: Submit signup
    post signup_path, params: {
      household_name: "The Hosted Family",
      organizer_name: "Alice",
      email: "alice@example.com",
      pin: "4826",
      **terms_assent_params
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
    assert member.verify_pin("4826")
    assert_not household.onboarded?
  end

  # @card-21.1
  test "hosted mode verify rejects incorrect code" do
    FamilyPlates.config.mode = "hosted"

    post signup_path, params: {
      household_name: "The Hosted Family",
      organizer_name: "Alice",
      email: "alice@example.com",
      pin: "4826",
      **terms_assent_params
    }

    assert_no_difference -> { Household.count } do
      post verify_signup_path, params: { code: "WRONG1" }
    end

    assert_response :unprocessable_entity
    assert_equal "Invalid or expired verification code.", flash[:alert]
  end

  test "hosted signup stops emailing an address after repeated attempts" do
    FamilyPlates.config.mode = "hosted"
    params = { household_name: "The Bakers", organizer_name: "Baker", email: "baker@example.com", pin: "4826", **terms_assent_params }

    5.times do
      post signup_path, params: params
      assert_redirected_to verify_signup_path
    end

    assert_no_difference -> { MagicCode.count } do
      assert_no_enqueued_emails do
        post signup_path, params: params
      end
    end

    assert_redirected_to new_signup_path
    assert_equal "Too many signup attempts. Please wait a few minutes and try again.", flash[:alert]
  end

  test "hosted signup stops accepting verification guesses" do
    FamilyPlates.config.mode = "hosted"
    post signup_path, params: {
      household_name: "The Hosted Family", organizer_name: "Alice", email: "alice@example.com", pin: "4826", **terms_assent_params
    }
    code = MagicCode.find_by!(email: "alice@example.com").code

    10.times do
      post verify_signup_path, params: { code: "WRONG1" }
      assert_response :unprocessable_entity
    end

    assert_no_difference -> { Household.count } do
      post verify_signup_path, params: { code: code }
    end

    assert_redirected_to verify_signup_path
    assert_equal "Too many signup attempts. Please wait a few minutes and try again.", flash[:alert]
    # Five wrong guesses already destroyed the code, so the right one is useless too.
    assert_not MagicCode.exists?(email: "alice@example.com")
  end

  test "hosted signup rejects an oversized household name before sending a code" do
    FamilyPlates.config.mode = "hosted"

    assert_no_difference -> { MagicCode.count } do
      assert_no_enqueued_emails do
        post signup_path, params: {
          household_name: "A" * 500,
          organizer_name: "Baker",
          email: "baker@example.com",
          pin: "4826",
          **terms_assent_params
        }
      end
    end

    assert_response :unprocessable_entity
  end

  test "appliance mode create provisions household and organizer immediately" do
    assert_difference -> { Household.count } => 1, -> { User.count } => 1, -> { FamilyMember.count } => 1 do
      post signup_path, params: {
        household_name: "Appliance Family",
        organizer_name: "Chef Head",
        email: "chefhead@example.com",
        pin: "4826"
      }
    end

    assert_redirected_to onboarding_recipes_path
    assert cookies[:session_token].present?
    assert cookies[:active_family_member_id].present?
  end

  test "appliance signup does not ask for terms acceptance" do
    get new_signup_path

    assert_select "input[name=accept_terms]", false
  end

  test "hosted signup form asks for terms acceptance and links the legal pages" do
    FamilyPlates.config.mode = "hosted"
    get new_signup_path

    assert_select "input[type=checkbox][name=accept_terms][required]"
    assert_select "form a[href=?]", terms_path
    assert_select "form a[href=?]", privacy_path
  end

  test "hosted signup without terms acceptance sends no code" do
    FamilyPlates.config.mode = "hosted"

    assert_no_difference -> { MagicCode.count } do
      assert_no_enqueued_emails do
        post signup_path, params: {
          household_name: "The Bakers", organizer_name: "Baker", email: "baker@example.com", pin: "4826"
        }
      end
    end

    assert_response :unprocessable_entity
    assert_equal TermsAssent::ALERT, flash[:alert]
  end

  test "hosted signup records the accepted terms version on the user" do
    FamilyPlates.config.mode = "hosted"
    post signup_path, params: {
      household_name: "The Hosted Family", organizer_name: "Alice", email: "alice@example.com", pin: "4826", **terms_assent_params
    }

    freeze_time do
      post verify_signup_path, params: { code: MagicCode.find_by!(email: "alice@example.com").code }

      user = User.find_by!(email: "alice@example.com")
      assert_equal Legal::TERMS_VERSION, user.terms_version
      assert_equal Time.current, user.terms_accepted_at
    end
  end

  test "the verified hosted creator becomes the household's billing owner" do
    FamilyPlates.config.mode = "hosted"
    post signup_path, params: {
      household_name: "The Hosted Family", organizer_name: "Alice", email: "alice@example.com", pin: "4826", **terms_assent_params
    }
    assert_no_difference -> { Household.where.not(billing_owner_user_id: nil).count },
      "an unverified signup must not create an owned household" do
      post verify_signup_path, params: { code: "WRONG1" }
    end

    post verify_signup_path, params: { code: MagicCode.find_by!(email: "alice@example.com").code }

    user = User.find_by!(email: "alice@example.com")
    household = Household.find_by!(name: "The Hosted Family")
    assert_equal user, household.billing_owner
  end

  test "a signed-in user who opens a hosted household becomes its billing owner" do
    FamilyPlates.config.mode = "hosted"
    user = User.create!(email: "returning@example.com")
    sign_in_user(user)

    post signup_path, params: {
      household_name: "Second Kitchen", organizer_name: "Ret", email: "returning@example.com", pin: "4826", **terms_assent_params
    }

    assert_redirected_to onboarding_recipes_path
    assert_equal user, Household.find_by!(name: "Second Kitchen").billing_owner
  end

  test "an appliance household has no billing owner" do
    post signup_path, params: {
      household_name: "Appliance Family", organizer_name: "Chef Head", email: "chefhead@example.com", pin: "4826"
    }

    assert_nil Household.find_by!(name: "Appliance Family").billing_owner_user_id
  end
end
