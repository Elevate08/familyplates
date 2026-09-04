require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    FamilyPlates.config.reset!
  end

  teardown do
    FamilyPlates.config.reset!
  end

  test "new renders sign-in form in appliance mode" do
    get new_session_path
    assert_response :success
    assert_select "h1", text: /Appliance Sign In/i
  end

  test "create in appliance mode with valid credentials succeeds" do
    user = User.create!(email: "parent@example.com", password: "valid-password123")

    post session_path, params: { email: "parent@example.com", password: "valid-password123" }

    assert_redirected_to root_url
    assert cookies[:session_token].present?
    assert_equal "Signed in successfully.", flash[:notice]
  end

  test "create in appliance mode with invalid password returns generic error and 422" do
    User.create!(email: "parent@example.com", password: "valid-password123")

    post session_path, params: { email: "parent@example.com", password: "wrong-password" }

    assert_response :unprocessable_entity
    assert_equal "Invalid email or password.", flash[:alert]
    assert_nil cookies[:session_token]
  end

  test "create in appliance mode with unknown email returns identical generic error (enumeration-safe)" do
    post session_path, params: { email: "unknown@example.com", password: "any-password" }

    assert_response :unprocessable_entity
    assert_equal "Invalid email or password.", flash[:alert]
    assert_nil cookies[:session_token]
  end

  test "create in appliance mode with passwordless user returns identical generic error" do
    User.create!(email: "nopass@example.com")

    post session_path, params: { email: "nopass@example.com", password: "any-password" }

    assert_response :unprocessable_entity
    assert_equal "Invalid email or password.", flash[:alert]
    assert_nil cookies[:session_token]
  end

  test "create in appliance mode rate limits after 10 attempts" do
    email = "target@example.com"
    10.times do
      post session_path, params: { email: email, password: "bad" }
      assert_response :unprocessable_entity
    end

    post session_path, params: { email: email, password: "bad" }
    assert_redirected_to new_session_path
    assert_equal "Too many sign-in attempts. Please wait a few minutes and try again.", flash[:alert]
  end

  test "hosted mode renders hosted sign-in and sends 6-character code" do
    FamilyPlates.config.mode = "hosted"
    user = User.create!(email: "hosted@example.com")

    get new_session_path
    assert_response :success
    assert_select "h1", text: /Sign in to FamilyPlates/i

    assert_enqueued_emails 1 do
      post session_path, params: { email: "hosted@example.com" }
    end

    assert_redirected_to verify_session_path
    magic_code = user.magic_codes.last
    assert_not_nil magic_code
    assert_match(/\A[A-Z0-9]{6}\z/, magic_code.code)
    assert magic_code.expires_at > Time.current
  end

  test "hosted mode flow is identical for unknown email (enumeration-safe)" do
    FamilyPlates.config.mode = "hosted"

    assert_no_emails do
      post session_path, params: { email: "stranger@example.com" }
    end

    assert_redirected_to verify_session_path
    assert_equal "If an account exists for that email, a 6-character code has been sent.", flash[:notice]
    assert_equal 0, MagicCode.where(email: "stranger@example.com").count
  end

  test "hosted mode verifies valid magic code, single-use destruction, and creates session" do
    FamilyPlates.config.mode = "hosted"
    user = User.create!(email: "hosted@example.com")
    magic_code = user.magic_codes.create!(email: user.email, code: "ABC123", expires_at: 15.minutes.from_now)

    post verify_session_path, params: { email: user.email, code: "abc123" }

    assert_redirected_to root_url
    assert cookies[:session_token].present?
    assert_not MagicCode.exists?(magic_code.id)
  end

  test "hosted mode rejects expired or invalid magic code with generic error" do
    FamilyPlates.config.mode = "hosted"
    user = User.create!(email: "hosted@example.com")
    user.magic_codes.create!(email: user.email, code: "ABC123", expires_at: 1.minute.ago)

    post verify_session_path, params: { email: user.email, code: "ABC123" }
    assert_response :unprocessable_entity
    assert_equal "Invalid or expired code.", flash[:alert]

    post verify_session_path, params: { email: user.email, code: "WRONG1" }
    assert_response :unprocessable_entity
    assert_equal "Invalid or expired code.", flash[:alert]
  end

  test "destroy clears active profile, session record, and session cookie" do
    user = User.create!(email: "parent@example.com", password: "password123")
    member = family_members(:one)
    member.update!(user: user)

    post session_path, params: { email: user.email, password: "password123" }
    assert cookies[:session_token].present?

    delete session_path

    assert_redirected_to select_profile_path
    assert cookies[:active_family_member_id].blank?
    assert cookies[:session_token].blank?
  end
end
