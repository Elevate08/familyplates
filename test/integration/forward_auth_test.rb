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

  # @card-20.1
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

  # @card-20.6
  test "forward-auth headers are ignored when request comes from untrusted proxy IP" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1", "10.0.0.7" ]

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

  # SA-01
  test "forward-auth ignores a spoofed X-Forwarded-For from an untrusted private peer" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1" ]

    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      get root_path, headers: {
        "Remote-Email" => "victim@example.com",
        "X-Forwarded-For" => "127.0.0.1",
        "REMOTE_ADDR" => "192.168.1.50"
      }

      assert_redirected_to select_profile_path
      assert cookies[:session_token].blank?
      assert_not User.exists?(email: "victim@example.com")
    end
  end

  # SA-01
  test "forward-auth does not link an existing user when X-Forwarded-For is spoofed" do
    existing_user = User.create!(email: "victim@example.com", password: "password123")
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1" ]

    assert_no_difference [ "Identity.count", "Session.count" ] do
      get root_path, headers: {
        "X-Forwarded-Email" => "victim@example.com",
        "X-Forwarded-For" => "127.0.0.1",
        "REMOTE_ADDR" => "10.0.0.7"
      }
    end

    assert cookies[:session_token].blank?
    assert_not existing_user.identities.exists?(provider: "forward_auth")
  end

  # SA-01: in the Docker image Puma sits behind Thruster, so REMOTE_ADDR is always
  # 127.0.0.1 and Thruster appends the address that connected to it as the last
  # X-Forwarded-For entry.
  test "forward-auth through Thruster refuses a client that spoofs the identity header" do
    FamilyPlates.config.forward_auth_enabled = true
    # default trusted list: 127.0.0.1, ::1
    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      get root_path, headers: {
        "Remote-Email" => "victim@example.com",
        "X-Forwarded-For" => "127.0.0.1, 192.168.1.50",
        "REMOTE_ADDR" => "127.0.0.1"
      }
    end

    assert_redirected_to select_profile_path
    assert cookies[:session_token].blank?
    assert_not User.exists?(email: "victim@example.com")
  end

  # SA-01
  test "forward-auth through Thruster trusts the proxy Thruster saw connect" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "172.18.0.5" ]

    assert_difference -> { User.count } => 1 do
      get root_path, headers: {
        "Remote-Email" => "proxied_user@example.com",
        "X-Forwarded-For" => "203.0.113.9, 172.18.0.5",
        "REMOTE_ADDR" => "127.0.0.1"
      }
    end

    assert_redirected_to select_profile_path
    assert cookies[:session_token].present?
  end

  # SA-01
  test "forward-auth through Thruster ignores a proxy address the client put in X-Forwarded-For" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "172.18.0.5" ]

    assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
      get root_path, headers: {
        "Remote-Email" => "victim@example.com",
        "X-Forwarded-For" => "172.18.0.5, 192.168.1.50",
        "REMOTE_ADDR" => "127.0.0.1"
      }
    end

    assert cookies[:session_token].blank?
  end

  # SA-01
  test "forward-auth through Thruster reads an IPv4-mapped IPv6 proxy address" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "172.18.0.5" ]

    assert_difference -> { User.count } => 1 do
      get root_path, headers: {
        "Remote-Email" => "mapped_user@example.com",
        "X-Forwarded-For" => "203.0.113.9, ::ffff:172.18.0.5",
        "REMOTE_ADDR" => "::ffff:127.0.0.1"
      }
    end
  end

  # SA-01: Thruster can also connect over IPv6 loopback.
  test "forward-auth from an IPv6 loopback peer refuses a spoofed last X-Forwarded-For entry" do
    FamilyPlates.config.forward_auth_enabled = true

    assert_no_difference [ "User.count", "Session.count" ] do
      get root_path, headers: {
        "Remote-Email" => "victim@example.com",
        "X-Forwarded-For" => "192.168.1.50",
        "REMOTE_ADDR" => "::1"
      }
    end
    assert cookies[:session_token].blank?
  end

  # SA-01
  test "forward-auth from an IPv6 loopback peer trusts a trusted last X-Forwarded-For entry" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "172.18.0.5" ]

    assert_difference -> { User.count } => 1 do
      get root_path, headers: {
        "Remote-Email" => "ipv6_loopback@example.com",
        "X-Forwarded-For" => "203.0.113.9, 172.18.0.5",
        "REMOTE_ADDR" => "::1"
      }
    end
    assert cookies[:session_token].present?
  end

  # SA-11
  test "a range entry in the trusted list no longer trusts a host inside it" do
    FamilyPlates.config.forward_auth_enabled = true

    [
      [ "10.0.0.0/8", "10.9.8.7" ],
      [ "172.18.0.0/16", "172.18.0.5" ],
      [ "::ffff:172.18.0.0/112", "172.18.0.5" ]
    ].each do |entry, peer|
      FamilyPlates.config.forward_auth_trusted_proxies = [ entry ]

      # Direct connection, and through Thruster (loopback peer, last X-Forwarded-For entry).
      assert_no_difference [ "User.count", "Identity.count", "Session.count" ], "direct peer #{peer} in #{entry}" do
        get root_path, headers: { "Remote-Email" => "victim@example.com", "REMOTE_ADDR" => peer }
      end
      assert_no_difference [ "User.count", "Identity.count", "Session.count" ], "Thruster hop #{peer} in #{entry}" do
        get root_path, headers: {
          "Remote-Email" => "victim@example.com",
          "X-Forwarded-For" => "203.0.113.9, #{peer}",
          "REMOTE_ADDR" => "127.0.0.1"
        }
      end
      assert cookies[:session_token].blank?
      assert_not User.exists?(email: "victim@example.com")
    end
  end

  # SA-11
  test "a range entry does not stop a single address in the same list from working" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "10.0.0.0/8", "172.18.0.5" ]

    assert_no_difference "User.count" do
      get root_path, headers: { "Remote-Email" => "lan@example.com", "REMOTE_ADDR" => "10.9.8.7" }
    end
    assert_difference -> { User.count } => 1 do
      get root_path, headers: { "Remote-Email" => "proxy@example.com", "REMOTE_ADDR" => "172.18.0.5" }
    end
  end

  # SA-11
  test "an explicit host-length prefix in the trusted list still works" do
    FamilyPlates.config.forward_auth_enabled = true

    [ "172.18.0.5/32", "::ffff:172.18.0.5/128", "fd00::5/128" ].each_with_index do |entry, i|
      FamilyPlates.config.forward_auth_trusted_proxies = [ entry ]
      peer = entry.start_with?("fd00") ? "fd00::5" : "172.18.0.5"

      assert_difference -> { User.count } => 1 do
        get root_path, headers: { "Remote-Email" => "host#{i}@example.com", "REMOTE_ADDR" => peer }
      end
    end
  end

  # SA-11
  test "an IPv6 range entry does not trust a host inside it" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "fd00::/64" ]

    assert_no_difference [ "User.count", "Session.count" ] do
      get root_path, headers: { "Remote-Email" => "victim@example.com", "REMOTE_ADDR" => "fd00::5" }
    end
  end

  # SA-11
  test "ignored range entries are logged once per process, naming the entries" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "172.18.0.5", "10.0.0.0/8", "::ffff:172.18.0.0/112" ]
    io = StringIO.new
    capture = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(capture)

    begin
      3.times do
        get root_path, headers: { "Remote-Email" => "a@example.com", "REMOTE_ADDR" => "10.9.8.7" }
      end
    ensure
      Rails.logger.stop_broadcasting_to(capture)
    end

    assert_equal 1, io.string.scan("[auth] forward_auth_trusted_proxies ignored range entries:").size
    assert_includes io.string, "ignored range entries: 10.0.0.0/8, ::ffff:172.18.0.0/112"
    assert_not_includes io.string, "172.18.0.5,"
  end

  # SA-11
  test "no range warning is logged when every entry is a single address" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "172.18.0.5", "127.0.0.1/32" ]
    io = StringIO.new
    capture = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(capture)

    begin
      get root_path, headers: { "Remote-Email" => "a@example.com", "REMOTE_ADDR" => "172.18.0.5" }
    ensure
      Rails.logger.stop_broadcasting_to(capture)
    end

    assert_not_includes io.string, "ignored range entries"
  end

  # SA-01
  test "forward-auth with a direct non-loopback trusted peer uses REMOTE_ADDR, not X-Forwarded-For" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "172.18.0.5" ]

    assert_difference -> { User.count } => 1 do
      get root_path, headers: {
        "Remote-Email" => "direct_user@example.com",
        "X-Forwarded-For" => "203.0.113.9",
        "REMOTE_ADDR" => "172.18.0.5"
      }
    end
    assert cookies[:session_token].present?
  end

  # SA-01
  test "forward-auth normalises an IPv4-mapped IPv6 direct peer" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "172.18.0.5" ]

    assert_difference -> { User.count } => 1 do
      get root_path, headers: {
        "Remote-Email" => "mapped_direct@example.com",
        "REMOTE_ADDR" => "::ffff:172.18.0.5"
      }
    end
  end

  # SA-01
  test "forward-auth refuses an unparseable or blank peer" do
    FamilyPlates.config.forward_auth_enabled = true

    assert_no_difference "User.count" do
      get root_path, headers: { "Remote-Email" => "a@example.com", "REMOTE_ADDR" => "" }
      get root_path, headers: {
        "Remote-Email" => "b@example.com",
        "X-Forwarded-For" => "127.0.0.1, not-an-ip",
        "REMOTE_ADDR" => "127.0.0.1"
      }
    end
  end

  # SA-01
  test "forward-auth refuses a blank last X-Forwarded-For field" do
    FamilyPlates.config.forward_auth_enabled = true

    assert_no_difference [ "User.count", "Session.count" ] do
      [ "127.0.0.1,", "127.0.0.1, " ].each do |forwarded|
        get root_path, headers: {
          "Remote-Email" => "blank_tail@example.com",
          "X-Forwarded-For" => forwarded,
          "REMOTE_ADDR" => "127.0.0.1"
        }
      end
    end
    assert cookies[:session_token].blank?
  end

  # SA-01
  test "forward-auth refuses a blank or whitespace-only X-Forwarded-For from a loopback peer" do
    FamilyPlates.config.forward_auth_enabled = true

    assert_no_difference [ "User.count", "Session.count" ] do
      [ "", " ", "   " ].each do |forwarded|
        get root_path, headers: {
          "Remote-Email" => "blank_header@example.com",
          "X-Forwarded-For" => forwarded,
          "REMOTE_ADDR" => "127.0.0.1"
        }
      end
    end
    assert cookies[:session_token].blank?
  end

  # SA-01
  test "forward-auth refuses a range where an address is expected" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "172.18.0.0", "172.18.0.5" ]

    assert_no_difference [ "User.count", "Session.count" ] do
      [ "172.18.0.0/24", "172.18.0.5/16", "::ffff:172.18.0.0/112" ].each do |hop|
        get root_path, headers: {
          "Remote-Email" => "range@example.com",
          "X-Forwarded-For" => "203.0.113.9, #{hop}",
          "REMOTE_ADDR" => "127.0.0.1"
        }
      end
    end
    assert cookies[:session_token].blank?
  end

  # SA-01
  test "forward-auth accepts a host-length prefix on the hop" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "172.18.0.5" ]

    assert_difference -> { User.count } => 1 do
      get root_path, headers: {
        "Remote-Email" => "host_prefix@example.com",
        "X-Forwarded-For" => "203.0.113.9, 172.18.0.5/32",
        "REMOTE_ADDR" => "127.0.0.1"
      }
    end
  end

  # SA-01
  test "an IPv4-mapped IPv6 trusted-proxy entry matches the IPv4 peer" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "::ffff:172.18.0.5" ]

    assert_difference -> { User.count } => 1 do
      get root_path, headers: {
        "Remote-Email" => "mapped_entry@example.com",
        "REMOTE_ADDR" => "172.18.0.5"
      }
    end
  end

  # SA-01
  test "an IPv4-mapped IPv6 trusted-proxy entry does not match another IPv4 peer" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "::ffff:172.18.0.5" ]

    assert_no_difference "User.count" do
      get root_path, headers: {
        "Remote-Email" => "outside@example.com",
        "REMOTE_ADDR" => "172.18.0.6"
      }
    end
  end

  # SA-01
  test "an unparseable hop is logged as unparseable" do
    FamilyPlates.config.forward_auth_enabled = true
    io = StringIO.new
    capture = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(capture)

    begin
      get root_path, headers: {
        "Remote-Email" => "a@example.com",
        "X-Forwarded-For" => "127.0.0.1, not-an-ip",
        "REMOTE_ADDR" => "127.0.0.1"
      }
    ensure
      Rails.logger.stop_broadcasting_to(capture)
    end

    assert_includes io.string, "forward_auth_untrusted_peer peer=unparseable"
  end

  # SA-01
  test "a range where a hop is expected is logged as a range, not as unparseable" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "172.18.0.0" ]
    io = StringIO.new
    capture = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(capture)

    begin
      get root_path, headers: {
        "Remote-Email" => "a@example.com",
        "X-Forwarded-For" => "203.0.113.9, 172.18.0.0/24",
        "REMOTE_ADDR" => "127.0.0.1"
      }
    ensure
      Rails.logger.stop_broadcasting_to(capture)
    end

    assert_includes io.string, "forward_auth_untrusted_peer peer=range:172.18.0.0/24"
    assert_not_includes io.string, "peer=unparseable"
    assert cookies[:session_token].blank?
  end

  # SA-01
  test "an untrusted peer with identity headers is logged without header values" do
    FamilyPlates.config.forward_auth_enabled = true
    io = StringIO.new
    capture = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(capture)

    begin
      get root_path, headers: {
        "Remote-Email" => "secret_victim@example.com",
        "REMOTE_ADDR" => "192.168.1.50"
      }
      get root_path, headers: { "REMOTE_ADDR" => "192.168.1.51" }
    ensure
      Rails.logger.stop_broadcasting_to(capture)
    end

    assert_includes io.string, "[auth] forward_auth_untrusted_peer peer=192.168.1.50"
    assert_not_includes io.string, "forward_auth_untrusted_peer peer=192.168.1.51"
    assert_not_includes io.string, "secret_victim"
  end

  # @card-20.6
  test "trusted forward-auth provisions user and establishes session" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1" ]

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

  # @card-20.2
  test "trusted forward-auth links to existing user without creating duplicate account" do
    existing_user = User.create!(email: "existing_chef@example.com", password: "password123")
    @member.update!(user: existing_user)

    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1" ]

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

  # @card-20.7
  test "forward-auth sign out prevents immediate re-authentication until cleared" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1" ]

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

  # @card-20.7
  test "forward-auth sign out redirects to proxy logout URL when configured" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1" ]
    FamilyPlates.config.forward_auth_logout_url = "https://auth.example.com/outpost.goauthentik.io/sign_out"

    get root_path, headers: {
      "Remote-Email" => "operator@example.com",
      "REMOTE_ADDR" => "127.0.0.1"
    }

    delete session_path
    assert_redirected_to "https://auth.example.com/outpost.goauthentik.io/sign_out"
  end
end
