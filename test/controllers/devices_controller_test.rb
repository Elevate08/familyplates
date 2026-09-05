require "test_helper"

class DevicesControllerTest < ActionDispatch::IntegrationTest
  test "index redirects when unauthenticated" do
    get devices_path
    assert_redirected_to new_session_path
  end

  test "index lists sessions for signed-in user" do
    user = User.create!(email: "parent@example.com", password: "password123")
    post session_path, params: { email: user.email, password: "password123" }

    user.sessions.create!(token: "other-token", user_agent: "Safari Tablet", ip_address: "10.0.0.5")

    get devices_path
    assert_response :success
    assert_select "span", text: /Safari Tablet/
    assert_select "span", text: /Current Device/
  end

  test "destroy revokes a specific device" do
    user = User.create!(email: "parent@example.com", password: "password123")
    post session_path, params: { email: user.email, password: "password123" }
    other_session = user.sessions.create!(token: "other-token", user_agent: "Old Phone")

    assert_difference -> { user.sessions.count }, -1 do
      delete device_path(other_session)
    end

    assert_redirected_to devices_path
    assert_equal "Device access revoked.", flash[:notice]
  end

  test "destroy_all revokes all other devices while preserving current device" do
    user = User.create!(email: "parent@example.com", password: "password123")
    post session_path, params: { email: user.email, password: "password123" }

    user.sessions.create!(token: "other-token-1", user_agent: "Tablet 1")
    user.sessions.create!(token: "other-token-2", user_agent: "Tablet 2")

    assert_equal 3, user.sessions.count

    delete destroy_all_devices_path

    assert_redirected_to devices_path
    assert_equal 1, user.sessions.count
    assert_equal "All other devices have been signed out.", flash[:notice]
  end
end
