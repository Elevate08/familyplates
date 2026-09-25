# frozen_string_literal: true

require "test_helper"

class DevicePairingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "admin@example.com", password: "password123")
    @household = households(:one)
    @admin_member = family_members(:one)
    @admin_member.update!(user: @user)
  end

  test "index redirects to sign in when unauthenticated" do
    get pair_path
    assert_redirected_to new_session_path
    assert_equal "Please sign in to pair or approve a device.", flash[:alert]
  end

  test "index renders pairing code form when signed in" do
    sign_in_user
    get pair_path
    assert_response :success
    assert_select "input[name='user_code']"
  end

  test "index with user_code param redirects to verify" do
    sign_in_user
    get pair_path(user_code: "ABCD-EFGH")
    assert_redirected_to verify_pair_path(user_code: "ABCD-EFGH")
  end

  test "new creates device grant and renders QR pairing screen" do
    assert_difference -> { DeviceGrant.count } => 1 do
      get new_pair_path(kind: "kiosk")
    end
    assert_response :success
    assert_select "[data-controller='device-pairing']"
    assert_select "svg" # QR code SVG
  end

  test "kiosk route defaults to kiosk kind" do
    get "/kiosk"
    assert_response :success
    grant = DeviceGrant.order(:created_at).last
    assert_equal "kiosk", grant.kind
  end

  # @card-18.1
  test "device_authorization endpoint creates grant and returns RFC 8628 payload" do
    post device_authorization_pair_path, params: { kind: "kiosk", client_name: "Samsung Fridge" }
    assert_response :ok

    json = response.parsed_body
    assert json["device_code"].present?
    assert json["user_code"].present?
    assert_equal 5, json["interval"]
    assert_in_delta 900, json["expires_in"], 5
    assert_equal pair_url, json["verification_uri"]
  end

  test "token endpoint returns invalid_grant for nonexistent device code" do
    post token_pair_path, params: { device_code: "nonexistent" }
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
  end

  test "verify page requires sign in" do
    grant = DeviceGrant.create!
    get verify_pair_path(user_code: grant.user_code)
    assert_redirected_to new_session_path
    assert_equal "Please sign in to approve device pairing.", flash[:alert]
  end

  test "verify page shows grant info and selection form when signed in" do
    sign_in_user
    grant = DeviceGrant.create!(kind: "kiosk")

    get verify_pair_path(user_code: grant.user_code)
    assert_response :success
    assert_select "input[name='user_code'][value='#{grant.user_code}']"
    assert_select "input[type='radio'][value='kiosk']"
    assert_select "input[type='radio'][value='browser']"
  end

  test "verify page handles unknown or expired codes" do
    sign_in_user
    get verify_pair_path(user_code: "INVALID")
    assert_redirected_to pair_path
    assert_equal "Pairing code not found. Please check the code and try again.", flash[:alert]

    expired_grant = DeviceGrant.create!(expires_at: 1.minute.ago)
    get verify_pair_path(user_code: expired_grant.user_code)
    assert_redirected_to pair_path
    assert_equal "This pairing code has expired. Please refresh the device screen.", flash[:alert]
  end

  # @card-18.1
  test "approve creates session and marks grant approved" do
    sign_in_user
    grant = DeviceGrant.create!(kind: "kiosk")

    assert_difference -> { Session.count } => 1 do
      post approve_pair_path, params: { user_code: grant.user_code, kind: "kiosk" }
    end

    assert_redirected_to devices_path
    assert grant.reload.approved?
    assert_equal "kiosk", grant.session.kind
  end

  # @card-18.5
  test "deny marks grant denied" do
    sign_in_user
    grant = DeviceGrant.create!

    post deny_pair_path, params: { user_code: grant.user_code }
    assert_redirected_to pair_path
    assert grant.reload.denied?
  end

  private

  # @card-18.5
  test "token endpoint hands an approved device its session token exactly once" do
    grant = DeviceGrant.create!(kind: "kiosk")
    grant.approve!(by: @user, household: @household, kind: "kiosk")

    post token_pair_path, params: { device_code: grant.device_code }
    assert_response :ok
    token = response.parsed_body["access_token"]
    assert_equal grant.session, Session.find_by_token(token)
    assert_equal token, response.parsed_body["session_token"]
    assert grant.reload.redeemed?

    # Anyone else holding the device code - or a second poll - gets nothing.
    grant.update_columns(last_polled_at: 1.minute.ago)
    post token_pair_path, params: { device_code: grant.device_code }
    assert_response :bad_request
    assert_equal "invalid_grant", response.parsed_body["error"]
    assert_equal grant.session, Session.find_by_token(token), "the redeemed token keeps working"
  end

  test "verify treats a redeemed grant as already paired" do
    sign_in_user
    grant = DeviceGrant.create!(kind: "kiosk")
    grant.approve!(by: @user, household: @household, kind: "kiosk")
    grant.redeem!

    get verify_pair_path(user_code: grant.user_code)
    assert_redirected_to devices_path
  end

  def sign_in_user
    post session_path, params: { email: @user.email, password: "password123" }
    assert_redirected_to root_url
  end
end
