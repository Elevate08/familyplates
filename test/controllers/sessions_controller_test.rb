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

  # @card-15.1
  test "create in appliance mode with invalid password returns generic error and 422" do
    User.create!(email: "parent@example.com", password: "valid-password123")

    post session_path, params: { email: "parent@example.com", password: "wrong-password" }

    assert_response :unprocessable_entity
    assert_equal "Invalid email or password.", flash[:alert]
    assert_nil cookies[:session_token]
  end

  # @card-15.1
  test "create in appliance mode with unknown email returns identical generic error (enumeration-safe)" do
    post session_path, params: { email: "unknown@example.com", password: "any-password" }

    assert_response :unprocessable_entity
    assert_equal "Invalid email or password.", flash[:alert]
    assert_nil cookies[:session_token]
  end

  # @card-15.1
  test "create in appliance mode with passwordless user returns identical generic error" do
    User.create!(email: "nopass@example.com")

    post session_path, params: { email: "nopass@example.com", password: "any-password" }

    assert_response :unprocessable_entity
    assert_equal "Invalid email or password.", flash[:alert]
    assert_nil cookies[:session_token]
  end

  # @card-15.2
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

  # @card-17.2
  test "signing into another account clears the previous organizer profile" do
    first_user = User.create!(email: "first@example.com", password: "password123")
    second_user = User.create!(email: "second@example.com", password: "password123")
    family_members(:one).update!(user: first_user)
    FamilyPlates.config.require_login = true

    post session_path, params: { email: first_user.email, password: "password123" }
    assert_equal family_members(:one).id, active_family_member_id

    post session_path, params: { email: second_user.email, password: "password123" }
    get admin_root_path

    assert_redirected_to select_profile_path
    assert_nil active_family_member_id
  end

  test "signed_out renders kiosk signed out screen with pair again button" do
    get signed_out_path(kind: "kiosk")
    assert_response :success
    assert_includes response.body, "Kitchen Display Signed Out"
    assert_includes response.body, "Sign In Again"
    assert_select "a[href=?]", new_pair_path(kind: "kiosk")
  end

  test "signed_out renders browser signed out screen with sign in again options" do
    get signed_out_path(kind: "browser")
    assert_response :success
    assert_includes response.body, "Device Signed Out"
    assert_includes response.body, "Sign In Again"
    assert_select "a[href=?]", new_session_path
  end
end
