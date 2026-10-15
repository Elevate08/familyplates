# frozen_string_literal: true

require "test_helper"

# FP-APPSEC-003: the Deny button was nested inside the approve form. Browsers
# discard a nested <form>, so Deny submitted approval.
class DevicePairingVerifyFormsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "pairing-forms@example.com", password: "password123")
    family_members(:one).update!(user: @user)
    post session_path, params: { email: @user.email, password: "password123" }
    assert_redirected_to root_url
    @grant = DeviceGrant.create!(kind: "kiosk")
  end

  test "verify page has no form nested inside another form" do
    get verify_pair_path(user_code: @grant.user_code)
    assert_response :success

    assert_select "form form", count: 0
  end

  test "deny control submits to deny path, not approve path" do
    get verify_pair_path(user_code: @grant.user_code)
    assert_response :success

    deny_path = deny_pair_path(user_code: @grant.user_code)
    assert_select "form[action='#{deny_path}'] button", text: "Deny Request"
    assert_select "form[action='#{approve_pair_path}'] button", text: "Deny Request", count: 0
    assert_select "form[action='#{approve_pair_path}'] input[name='user_code'][value='#{@grant.user_code}']"
  end
end
