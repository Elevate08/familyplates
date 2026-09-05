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

    # Separate integration session simulating the kitchen tablet
    tablet = open_session
    tablet.post token_pair_path, params: { device_code: grant.device_code }
    tablet.assert_response :success
    assert_equal "kiosk", tablet.signed_cookie(:device_kind)
    assert tablet.cookies[:session_token].present?

    # Tablet selects admin profile and browses recipes
    tablet.post set_profile_path(@admin_member), params: { pin: "1234" }
    tablet.assert_redirected_to root_url
    assert tablet.cookies[:active_family_member_id].present?
    tablet.get recipes_path
    tablet.assert_response :success

    # Parent signs in on laptop
    post session_path, params: { email: @user.email, password: "password123" }
    post set_profile_path(@admin_member), params: { pin: "1234" }

    # View devices list
    get devices_path
    assert_response :success
    assert_includes response.body, "KitchenTablet/1.0"
    assert_includes response.body, "kiosk"

    # Revoke kiosk session from laptop
    assert_difference -> { Session.where(id: kiosk_session.id).count }, -1 do
      delete device_path(kiosk_session)
    end
    assert_redirected_to devices_path
    assert_equal "Device access revoked.", flash[:notice]

    # Now verify tablet refreshing the page is immediately kicked out to signed-out screen
    tablet.get root_path
    tablet.assert_redirected_to signed_out_path(kind: "kiosk")
    assert_equal "This kitchen display's access has been revoked.", tablet.flash[:alert]

    # Verify all credentials and active profile cookies were purged on tablet
    assert tablet.cookies[:session_token].blank?
    assert tablet.cookies[:active_family_member_id].blank?
    assert tablet.cookies[:device_kind].blank?

    # Following redirect shows signed out page with a button to pair/sign in again
    tablet.follow_redirect!
    tablet.assert_response :success
    assert_includes tablet.response.body, "Kitchen Display Signed Out"
    assert_includes tablet.response.body, "Sign In Again"

    # Clicking 'Sign In Again' button shows the pair code
    tablet.get new_pair_path(kind: "kiosk")
    tablet.assert_response :success
    assert_includes tablet.response.body, "Pair Kitchen Display"

    # Now verify tablet polling with destroyed session is rejected
    travel 6.seconds do
      tablet.post token_pair_path, params: { device_code: grant.device_code }
      tablet.assert_response :bad_request
      assert_equal "invalid_grant", tablet.response.parsed_body["error"]
    end

    # Attempting to navigate or switch profile on the tablet without pairing is denied
    tablet.get recipes_path
    tablet.assert_redirected_to select_profile_path
  end

  test "revoking browser device from devices list terminates browser session and profile" do
    laptop = open_session
    laptop.post session_path, params: { email: @user.email, password: "password123" }
    laptop.post set_profile_path(@admin_member), params: { pin: "1234" }
    laptop_session = @user.sessions.order(:created_at).last
    assert_equal "browser", laptop_session.kind

    # Phone signs in and revokes laptop session
    phone = open_session
    phone.post session_path, params: { email: @user.email, password: "password123" }
    phone.post set_profile_path(@admin_member), params: { pin: "1234" }
    phone.delete device_path(laptop_session)
    phone.assert_redirected_to devices_path

    # Laptop attempts to refresh page
    laptop.get recipes_path
    laptop.assert_redirected_to signed_out_path(kind: "browser")
    assert_equal "Device access has been revoked.", laptop.flash[:alert]
    assert laptop.cookies[:session_token].blank?
    assert laptop.cookies[:active_family_member_id].blank?

    # Signed out page provides option to sign in again
    laptop.follow_redirect!
    laptop.assert_response :success
    assert_includes laptop.response.body, "Device Signed Out"
    assert_includes laptop.response.body, "Sign In Again"
  end

  test "revoking kiosk session prevents switching profile and redirects with revocation notice" do
    grant = DeviceGrant.create!(kind: "kiosk")
    grant.approve!(by: @user, household: @household, kind: "kiosk")
    kiosk_session = grant.session

    tablet = open_session
    tablet.post token_pair_path, params: { device_code: grant.device_code }
    tablet.post set_profile_path(@admin_member), params: { pin: "1234" }

    other_member = family_members(:two)

    # Admin signs in and revokes session from laptop
    post session_path, params: { email: @user.email, password: "password123" }
    delete device_path(kiosk_session)
    assert_redirected_to devices_path

    # Tablet attempts to switch profile to other_member
    tablet.post switch_family_member_path(other_member)
    tablet.assert_redirected_to signed_out_path(kind: "kiosk")
    assert_equal "This kitchen display's access has been revoked.", tablet.flash[:alert]

    # Cookies must be cleared
    assert tablet.cookies[:session_token].blank?
    assert tablet.cookies[:active_family_member_id].blank?
    assert tablet.cookies[:device_kind].blank?
  end

  test "revoking kiosk session prevents navigating to protected pages and redirects to kiosk pairing" do
    grant = DeviceGrant.create!(kind: "kiosk")
    grant.approve!(by: @user, household: @household, kind: "kiosk")
    kiosk_session = grant.session

    tablet = open_session
    tablet.post token_pair_path, params: { device_code: grant.device_code }
    tablet.post set_profile_path(@admin_member), params: { pin: "1234" }

    # Admin signs in and revokes session from laptop
    post session_path, params: { email: @user.email, password: "password123" }
    delete device_path(kiosk_session)
    assert_redirected_to devices_path

    # Tablet navigates to recipes_path
    tablet.get recipes_path
    tablet.assert_redirected_to signed_out_path(kind: "kiosk")
    assert_equal "This kitchen display's access has been revoked.", tablet.flash[:alert]

    # Cookies must be cleared
    assert tablet.cookies[:session_token].blank?
    assert tablet.cookies[:active_family_member_id].blank?
    assert tablet.cookies[:device_kind].blank?
  end

  test "kiosk session with active admin member cannot modify PIN or access PIN inputs in preferences" do
    grant = DeviceGrant.create!(kind: "kiosk")
    grant.approve!(by: @user, household: @household, kind: "kiosk")
    post token_pair_path, params: { device_code: grant.device_code }
    assert_response :success

    # Select admin profile on kiosk
    post set_profile_path(@admin_member), params: { pin: "1234" }
    assert_redirected_to root_url

    # Visit preferences page on kiosk
    get edit_preferences_path
    assert_response :success
    assert_includes response.body, "Kiosk Device Protection"
    assert_includes response.body, "Confirm with Admin 4-Digit PIN"
    assert_select "input[name='current_pin']", 1
    assert_select "input[name='family_member[pin]']", 0
    assert_not_includes response.body, "+ Add Member"

    # Attempt to modify name without current_pin on kiosk: rejected
    patch preferences_path, params: {
      family_member: {
        name: "Hacked Admin"
      }
    }
    assert_response :unprocessable_entity
    assert_includes response.body, "Please enter your current 4-digit PIN to confirm changes"
    @admin_member.reload
    assert_not_equal "Hacked Admin", @admin_member.name

    # Attempt to modify PIN on kiosk even with valid current_pin: name is updated, but pin is ignored
    patch preferences_path, params: {
      current_pin: "1234",
      family_member: {
        name: "Renamed Admin",
        pin: "9999"
      }
    }
    assert_redirected_to edit_preferences_path

    @admin_member.reload
    assert_equal "Renamed Admin", @admin_member.name
    assert @admin_member.verify_pin("1234"), "Original PIN must remain unchanged"
    assert_not @admin_member.verify_pin("9999"), "New PIN must not be saved from kiosk session"
  end
end
