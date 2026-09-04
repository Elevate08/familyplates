# frozen_string_literal: true

require "test_helper"

class KioskDevicePairingTest < ActionDispatch::IntegrationTest
  setup do
    FamilyPlates.config.reset!
    @household = households(:one)
    @admin_member = family_members(:one)
    @user = User.create!(email: "parent@example.com", password: "password123")
    @admin_member.update!(user: @user)
  end

  teardown do
    FamilyPlates.config.reset!
  end

  test "complete RFC 8628 kiosk device pairing flow" do
    # 1. Device initiates authorization grant (e.g. wall tablet)
    post device_authorization_pair_path, params: { kind: "kiosk", client_name: "Kitchen Wall Display" }
    assert_response :success
    auth_data = response.parsed_body

    assert auth_data["device_code"].present?
    assert auth_data["user_code"].present?
    assert_equal 5, auth_data["interval"]
    assert_in_delta 900, auth_data["expires_in"], 5
    assert_includes auth_data["verification_uri_complete"], auth_data["user_code"]

    device_code = auth_data["device_code"]
    user_code = auth_data["user_code"]

    # 2. Device polls token endpoint before approval -> authorization_pending
    post token_pair_path, params: { device_code: device_code }
    assert_response :bad_request
    poll_data = response.parsed_body
    assert_equal "authorization_pending", poll_data["error"]

    # 3. Device polls too quickly (< 5 seconds) -> slow_down
    post token_pair_path, params: { device_code: device_code }
    assert_response :bad_request
    slow_down_data = response.parsed_body
    assert_equal "slow_down", slow_down_data["error"]

    # 4. Stranger (unauthenticated) scanning QR code is redirected to sign in
    get verify_pair_path(user_code: user_code)
    assert_redirected_to new_session_path
    assert_equal "Please sign in to approve device pairing.", flash[:alert]

    # 5. User signs in on their phone and is returned to verification prompt
    post session_path, params: { email: @user.email, password: "password123" }
    assert_redirected_to verify_pair_path(user_code: user_code)

    follow_redirect!
    assert_response :success
    assert_includes response.body, user_code
    assert_includes response.body, "Kitchen Display (Kiosk)"

    # 6. User approves pairing as kiosk
    assert_difference -> { @user.sessions.where(kind: "kiosk").count } => 1 do
      post approve_pair_path, params: { user_code: user_code, kind: "kiosk" }
    end
    assert_redirected_to devices_path
    assert_equal "Device successfully paired as kiosk.", flash[:notice]

    # 7. Device polls again (wait until interval passes)
    travel 6.seconds do
      post token_pair_path, params: { device_code: device_code }
      assert_response :success
      token_data = response.parsed_body
      assert_equal "kiosk", token_data["kind"]
      assert_equal "Bearer", token_data["token_type"]
      assert token_data["access_token"].present?
      assert_equal cookies[:session_token], response.cookies["session_token"]
    end
  end

  test "kiosk session does not expire and can switch profiles but cannot access admin tools" do
    # Pair device as kiosk via real grant
    grant = DeviceGrant.create!(kind: "kiosk")
    grant.approve!(by: @user, household: @household, kind: "kiosk")
    post token_pair_path, params: { device_code: grant.device_code }
    assert_response :success
    kiosk_session = grant.session

    # Age the session beyond normal idle (30d) and absolute (90d) limits
    kiosk_session.update_columns(last_active_at: 60.days.ago, created_at: 100.days.ago)
    assert_not kiosk_session.expired?

    # Kiosk visits root -> redirected to select profile
    get root_path
    assert_redirected_to select_profile_path

    # Kiosk visits profile picker -> can view profiles
    get select_profile_path
    assert_response :success
    assert_includes response.body, @admin_member.name

    # Select admin profile with valid PIN
    post set_profile_path(@admin_member), params: { pin: "1234" }
    assert_redirected_to root_url
    assert signed_in_as?(@admin_member)

    # Kiosk can view meal plan
    get root_path
    assert_redirected_to meal_plan_path(@household.current_meal_plan)
    follow_redirect!
    assert_response :success

    # Kiosk is FORBIDDEN from admin dashboard even though current_family_member is admin
    get admin_root_path
    assert_redirected_to root_path
    assert_equal "Kiosk devices cannot access household settings or admin tools.", flash[:alert]

    # Kiosk is FORBIDDEN from admin household edit
    get edit_admin_household_path
    assert_redirected_to root_path
    assert_equal "Kiosk devices cannot access household settings or admin tools.", flash[:alert]

    # Kiosk is FORBIDDEN from devices management
    get devices_path
    assert_redirected_to root_path
    assert_equal "Kiosk devices cannot manage connected devices.", flash[:alert]

    # Kiosk cannot approve new device pairing
    other_grant = DeviceGrant.create!
    post approve_pair_path, params: { user_code: other_grant.user_code }
    assert_redirected_to root_path
    assert_equal "Kiosk devices cannot approve new device pairings.", flash[:alert]
  end

  test "browser session pairing flow supports laptop sign-in with admin capabilities" do
    # Initiate browser pairing
    post device_authorization_pair_path, params: { kind: "browser" }
    assert_response :success
    grant_data = response.parsed_body

    # Sign in on mobile phone
    post session_path, params: { email: @user.email, password: "password123" }

    # Approve as browser
    post approve_pair_path, params: { user_code: grant_data["user_code"], kind: "browser" }
    assert_redirected_to devices_path

    # Laptop polls token
    travel 6.seconds do
      post token_pair_path, params: { device_code: grant_data["device_code"] }
      assert_response :success
      assert_equal "browser", response.parsed_body["kind"]

      # Adopt newly received browser session token
      cookies[:session_token] = response.cookies["session_token"]

      # Sign in as admin profile
      post set_profile_path(@admin_member), params: { pin: "1234" }
      assert_redirected_to root_url

      # Browser session CAN access admin tools
      get admin_root_path
      assert_response :success
    end
  end

  test "revoking kiosk device from devices list terminates kiosk access" do
    grant = DeviceGrant.create!(
      kind: "kiosk",
      ip_address: "10.0.0.99",
      user_agent: "KitchenTablet/1.0"
    )
    grant.approve!(by: @user, household: @household, kind: "kiosk")
    kiosk_session = grant.session

    # Parent signs in on laptop
    post session_path, params: { email: @user.email, password: "password123" }
    post set_profile_path(@admin_member), params: { pin: "1234" }

    # View devices list
    get devices_path
    assert_response :success
    assert_includes response.body, "KitchenTablet/1.0"
    assert_includes response.body, "kiosk"

    # Revoke kiosk session
    assert_difference -> { Session.where(id: kiosk_session.id).count }, -1 do
      delete device_path(kiosk_session)
    end
    assert_redirected_to devices_path
    assert_equal "Device access revoked.", flash[:notice]

    # Now verify tablet polling or requesting with that destroyed session is rejected
    post token_pair_path, params: { device_code: grant.device_code }
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end
end
