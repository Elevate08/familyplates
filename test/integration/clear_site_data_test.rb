require "test_helper"

# SA-05: signing out (or losing a session) must tell the browser to drop what it
# kept for this site, including the service worker's offline pages. Chromium
# honours the header on the redirect response itself; `"cache"` alone leaves
# Cache Storage in place, which is why `"storage"` is listed too.
class ClearSiteDataTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "parent@example.com", password: "password123")
    family_members(:one).update!(user: @user)
  end

  test "signing out clears the browser's cached pages" do
    post session_path, params: { email: @user.email, password: "password123" }
    assert_nil response.headers["Clear-Site-Data"], "signing in must not clear anything"

    delete session_path

    assert_redirected_to select_profile_path
    assert_equal ClearsSiteData::CLEAR_SITE_DATA, response.headers["Clear-Site-Data"]
  end

  test "signing out of a forward-auth session sent to the proxy logout URL still clears" do
    post session_path, params: { email: @user.email, password: "password123" }
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_logout_url = "https://auth.example.com/sign_out"

    delete session_path

    assert_redirected_to "https://auth.example.com/sign_out"
    assert_equal ClearsSiteData::CLEAR_SITE_DATA, response.headers["Clear-Site-Data"]
  ensure
    FamilyPlates.config.forward_auth_enabled = false
    FamilyPlates.config.forward_auth_logout_url = nil
  end

  test "revoking this device from the devices list clears the browser" do
    post session_path, params: { email: @user.email, password: "password123" }
    current = @user.sessions.order(:created_at).last

    delete device_path(current)

    assert_redirected_to signed_out_path(kind: "browser")
    assert_equal ClearsSiteData::CLEAR_SITE_DATA, response.headers["Clear-Site-Data"]
  end

  test "revoking another device leaves this browser's cache alone" do
    post session_path, params: { email: @user.email, password: "password123" }
    other = @user.sessions.create!(token: "other-token", user_agent: "Old Phone")

    delete device_path(other)

    assert_redirected_to devices_path
    assert_nil response.headers["Clear-Site-Data"]
  end

  test "a session revoked elsewhere clears the browser on the redirect to the signed-out page" do
    post session_path, params: { email: @user.email, password: "password123" }
    @user.sessions.destroy_all

    get recipes_path

    assert_redirected_to signed_out_path(kind: "browser")
    assert_equal ClearsSiteData::CLEAR_SITE_DATA, response.headers["Clear-Site-Data"]
  end

  test "a session revoked elsewhere clears the browser on the JSON 401" do
    post session_path, params: { email: @user.email, password: "password123" }
    @user.sessions.destroy_all

    get recipes_path, headers: { "Accept" => "application/json" }

    assert_response :unauthorized
    assert_equal "session_revoked", response.parsed_body["error"]
    assert_equal ClearsSiteData::CLEAR_SITE_DATA, response.headers["Clear-Site-Data"]
  end

  # The worker's offline pages are keyed by per-household numbers (/recipes/12), so another
  # household's page must not be left behind for the same address.
  test "switching to a profile in another household clears the browser" do
    other = Household.create!(name: "Second Home").family_members.create!(name: "Alex", role: "member", user: @user)
    post session_path, params: { email: @user.email, password: "password123" }

    post switch_family_member_path(other)

    assert_equal ClearsSiteData::CLEAR_SITE_DATA, response.headers["Clear-Site-Data"]
    assert signed_in_as?(other)
  end

  test "choosing a profile in another household from the profile picker clears the browser" do
    other = Household.create!(name: "Second Home").family_members.create!(name: "Alex", role: "member", user: @user)
    post session_path, params: { email: @user.email, password: "password123" }

    post set_profile_path(other)

    assert_equal ClearsSiteData::CLEAR_SITE_DATA, response.headers["Clear-Site-Data"]
    assert signed_in_as?(other)
  end

  test "switching profiles within one household leaves the browser alone" do
    sibling = family_members(:two)
    post session_path, params: { email: @user.email, password: "password123" }

    post switch_family_member_path(sibling)
    assert_nil response.headers["Clear-Site-Data"]
    assert signed_in_as?(sibling)

    post set_profile_path(family_members(:one)), params: { pin: "1234" }
    assert_nil response.headers["Clear-Site-Data"]
  end

  test "ordinary signed-in pages do not clear anything" do
    post session_path, params: { email: @user.email, password: "password123" }

    get recipes_path

    assert_response :success
    assert_nil response.headers["Clear-Site-Data"]
  end
end
