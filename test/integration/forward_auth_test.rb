require "test_helper"

class ForwardAuthTest < ActionDispatch::IntegrationTest
  setup do
    FamilyPlates.config.reset!
    @household = households(:one)
    @member = family_members(:one)
    FamilyPlates.config.require_login = false
  end

  teardown do
    FamilyPlates.config.reset!
  end

  test "forward-auth headers are completely ignored when disabled (default)" do
    assert_not FamilyPlates.config.forward_auth_enabled?

    assert_no_difference -> { User.count } do
      get root_path, headers: {
        "Remote-Email" => "proxyuser@example.com",
        "Remote-User" => "proxyuser",
        "REMOTE_ADDR" => "127.0.0.1"
      }

      assert_redirected_to select_profile_path
      assert cookies[:session_token].blank?
      assert_nil session[:active_family_member_id]
    end
  end

  test "forward-auth headers are ignored when request comes from untrusted proxy IP" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = ["127.0.0.1", "10.0.0.0/8"]

    assert_no_difference -> { User.count } do
      # Client IP from untrusted public IP spoofing reverse proxy header
      get root_path, headers: {
        "Remote-Email" => "hacker@example.com",
        "REMOTE_ADDR" => "198.51.100.42"
      }

      assert_redirected_to select_profile_path
      assert cookies[:session_token].blank?
      assert_not User.exists?(email: "hacker@example.com")
    end
  end

  test "trusted forward-auth provisions user and establishes session" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = ["127.0.0.1"]

    assert_difference -> { User.count } => 1, -> { Identity.count } => 1 do
      get root_path, headers: {
        "Remote-Email" => "authelia_user@example.com",
        "Remote-User" => "authelia_uid_101",
        "Remote-Name" => "Authelia User",
        "REMOTE_ADDR" => "127.0.0.1"
      }

      # User is provisioned, but has no family profile yet so redirects to select profile
      assert_redirected_to select_profile_path
      assert cookies[:session_token].present?
    end

    user = User.find_by!(email: "authelia_user@example.com")
    assert user.identities.exists?(provider: "forward_auth", uid: "authelia_uid_101")
  end

  test "trusted forward-auth links to existing user without creating duplicate account" do
    existing_user = User.create!(email: "existing_chef@example.com", password: "password123")
    @member.update!(user: existing_user)

    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = ["127.0.0.1"]

    assert_no_difference -> { User.count } do
      assert_difference -> { Identity.count } => 1 do
        get root_path, headers: {
          "X-Forwarded-Email" => "existing_chef@example.com",
          "X-Forwarded-User" => "authentik_chef",
          "REMOTE_ADDR" => "127.0.0.1"
        }

        # User is already linked to @member, so lands on home meal plan
        assert_redirected_to meal_plan_path(@household.current_meal_plan)
        assert cookies[:session_token].present?
      end
    end

    assert existing_user.identities.exists?(provider: "forward_auth", uid: "authentik_chef")
  end

  test "forward-auth sign out prevents immediate re-authentication until cleared" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = ["127.0.0.1"]

    # Initial request creates session
    get root_path, headers: {
      "Remote-Email" => "operator@example.com",
      "REMOTE_ADDR" => "127.0.0.1"
    }
    assert cookies[:session_token].present?

    # Sign out
    delete session_path
    assert_redirected_to select_profile_path

    # Next request with proxy header does not auto-login due to signed-out flag
    get root_path, headers: {
      "Remote-Email" => "operator@example.com",
      "REMOTE_ADDR" => "127.0.0.1"
    }
    assert cookies[:session_token].blank?
  end

  test "forward-auth sign out redirects to proxy logout URL when configured" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = ["127.0.0.1"]
    FamilyPlates.config.forward_auth_logout_url = "https://auth.example.com/outpost.goauthentik.io/sign_out"

    get root_path, headers: {
      "Remote-Email" => "operator@example.com",
      "REMOTE_ADDR" => "127.0.0.1"
    }

    delete session_path
    assert_redirected_to "https://auth.example.com/outpost.goauthentik.io/sign_out"
  end
end
