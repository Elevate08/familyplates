# frozen_string_literal: true

require "test_helper"

class PasskeysControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "passkey_test@example.com", password: "password123")
    @household = households(:one)
    @admin = family_members(:one)
    @admin.update!(user: @user)
  end

  test "index redirects when unauthenticated" do
    get passkeys_path
    assert_redirected_to new_session_path
    assert_equal "Please sign in to manage passkeys.", flash[:alert]
  end

  test "index renders passkeys list for signed-in user" do
    sign_in_user
    @user.passkeys.create!(external_id: "ext-1", public_key: "pk-1", nickname: "Work YubiKey")

    get passkeys_path
    assert_response :success
    assert_select "h3", text: /Work YubiKey/
  end

  test "index blocks kiosk sessions" do
    sign_in_user
    @user.sessions.last.update_columns(kind: "kiosk")

    get passkeys_path
    assert_redirected_to root_path
    assert_equal "Kiosk devices cannot manage passkeys.", flash[:alert]
  end

  test "registration_options returns challenge and user details" do
    sign_in_user

    post registration_options_passkeys_path
    assert_response :success
    json = response.parsed_body
    assert json["challenge"].present?
    assert json["user"].present?
    assert_equal @user.email, json["user"]["name"]
  end

  test "authentication_options is open to strangers and sets challenge" do
    post authentication_options_passkeys_path
    assert_response :success
    json = response.parsed_body
    assert json["challenge"].present?
  end

  test "destroy removes the passkey" do
    sign_in_user
    passkey = @user.passkeys.create!(external_id: "ext-to-remove", public_key: "pk-1", nickname: "Old Phone")

    assert_difference -> { @user.passkeys.count } => -1 do
      delete passkey_path(passkey)
    end

    assert_redirected_to passkeys_path
    assert_equal "Passkey removed.", flash[:notice]
  end

  private

  def sign_in_user
    post session_path, params: { email: @user.email, password: "password123" }
    assert_redirected_to root_url
  end
end
