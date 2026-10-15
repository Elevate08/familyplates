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
        "Remote-Email" => "victim@example.com",
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
  test "the boot warning names ignored range and unparseable entries" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "172.18.0.5", "10.0.0.0/8", "traefik", "::ffff:172.18.0.0/112" ]
    io = StringIO.new

    FamilyPlates.config.log_ignored_forward_auth_proxies(ActiveSupport::Logger.new(io))

    assert_equal "[auth] FORWARD_AUTH_TRUSTED_PROXIES ignored entries: 10.0.0.0/8 (range), " \
      "traefik (not an IP address), ::ffff:172.18.0.0/112 (range)\n",
      io.string
  end

  # SA-11
  test "the boot warning says when no usable address remains" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "10.0.0.0/8", "traefik" ]
    io = StringIO.new

    FamilyPlates.config.log_ignored_forward_auth_proxies(ActiveSupport::Logger.new(io))

    assert_equal "[auth] FORWARD_AUTH_TRUSTED_PROXIES ignored entries: 10.0.0.0/8 (range), traefik (not an IP address)\n" \
      "[auth] FORWARD_AUTH_TRUSTED_PROXIES has no usable address; forward-auth will not sign anyone in\n", io.string
  end

  # SA-11
  test "the boot warning is silent when forward-auth is off or every entry is a single address" do
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)

    FamilyPlates.config.forward_auth_enabled = false
    FamilyPlates.config.forward_auth_trusted_proxies = [ "10.0.0.0/8" ]
    FamilyPlates.config.log_ignored_forward_auth_proxies(logger)

    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "172.18.0.5", "127.0.0.1/32", "::1" ]
    FamilyPlates.config.log_ignored_forward_auth_proxies(logger)

    assert_empty io.string
  end

  # SA-11
  test "the request path does not log about ignored entries" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "10.0.0.0/8" ]
    io = StringIO.new
    capture = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(capture)

    begin
      get root_path, headers: { "Remote-Email" => "a@example.com", "REMOTE_ADDR" => "10.9.8.7" }
    ensure
      Rails.logger.stop_broadcasting_to(capture)
    end

    assert_not_includes io.string, "ignored entries"
  end

  # SA-11
  test "the parsed trusted list is memoized, and assignment and reset! clear it" do
    config = FamilyPlates.config
    config.forward_auth_trusted_proxies = [ "172.18.0.5", "10.0.0.0/8" ]
    first = config.forward_auth_proxies

    assert_same first, config.forward_auth_proxies
    assert_equal [ IPAddr.new("172.18.0.5") ], first.hosts
    assert_equal [ "10.0.0.0/8 (range)" ], first.ignored

    config.forward_auth_trusted_proxies = [ "172.18.0.6" ]
    assert_equal [ IPAddr.new("172.18.0.6") ], config.forward_auth_proxies.hosts
    assert_empty config.forward_auth_proxies.ignored

    assert_predicate first, :frozen?
    assert_predicate first.hosts, :frozen?
    assert_predicate first.ignored, :frozen?

    config.reset!
    saved = ENV.delete("FORWARD_AUTH_TRUSTED_PROXIES")
    begin
      assert_equal [ IPAddr.new("127.0.0.1"), IPAddr.new("::1") ], config.forward_auth_proxies.hosts
    ensure
      ENV["FORWARD_AUTH_TRUSTED_PROXIES"] = saved if saved
    end
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

    with_forward_auth_header_env("FORWARD_AUTH_USER_HEADERS" => "Remote-User") do
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

    with_forward_auth_header_env("FORWARD_AUTH_USER_HEADERS" => "Remote-User") do
      assert_no_difference -> { User.count } do
        assert_difference -> { Identity.count } => 1 do
          get root_path, headers: {
            "Remote-Email" => "existing_chef@example.com",
            "Remote-User" => "authentik_chef",
            "REMOTE_ADDR" => "127.0.0.1"
          }

          # User is already linked to @member, so lands on home meal plan
          assert_redirected_to meal_plan_path(@household.current_meal_plan)
          assert cookies[:session_token].present?
        end
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

  # SA-04
  test "by default only Remote-Email is read, so X-Forwarded-Email from a trusted hop is ignored" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1" ]

    with_forward_auth_header_env do
      assert_no_difference [ "User.count", "Session.count" ] do
        get root_path, headers: {
          "X-Forwarded-Email" => "oauth2proxy_user@example.com",
          "Tailscale-User-Login" => "tailscale_user@example.com",
          "REMOTE_ADDR" => "127.0.0.1"
        }
      end
      assert cookies[:session_token].blank?

      assert_difference "User.count", 1 do
        get root_path, headers: { "Remote-Email" => "authelia_default@example.com", "REMOTE_ADDR" => "127.0.0.1" }
      end
      assert cookies[:session_token].present?
    end
  end

  # SA-04
  test "an operator-set header list is read, and a client-added Remote-Email is ignored" do
    existing_user = User.create!(email: "victim@example.com", password: "password123")
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1" ]

    with_forward_auth_header_env("FORWARD_AUTH_EMAIL_HEADERS" => "X-Forwarded-Email") do
      get root_path, headers: {
        "X-Forwarded-Email" => "oauth2proxy_user@example.com",
        "Remote-Email" => "victim@example.com",
        "REMOTE_ADDR" => "127.0.0.1"
      }

      assert cookies[:session_token].present?
      assert User.exists?(email: "oauth2proxy_user@example.com")
      assert_not existing_user.identities.exists?(provider: "forward_auth")
    end
  end

  # SA-04
  test "an operator can list several headers and the first one present is used" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1" ]

    with_forward_auth_header_env("FORWARD_AUTH_EMAIL_HEADERS" => "Remote-Email, Tailscale-User-Login") do
      get root_path, headers: { "Tailscale-User-Login" => "tailnet_user@example.com", "REMOTE_ADDR" => "127.0.0.1" }

      assert cookies[:session_token].present?
      assert User.exists?(email: "tailnet_user@example.com")
    end
  end

  # SA-04
  test "the name header defaults to Remote-Name and the user ID header is only read when set" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1" ]
    headers = {
      "Remote-Email" => "uid_user@example.com",
      "Remote-User" => "remote_uid",
      "X-Forwarded-User" => "client_uid",
      "REMOTE_ADDR" => "127.0.0.1"
    }

    with_forward_auth_header_env do
      get root_path, headers: headers
      assert_equal [ "uid_user@example.com" ], User.find_by!(email: "uid_user@example.com").identities.pluck(:uid)
    end

    with_forward_auth_header_env("FORWARD_AUTH_USER_HEADERS" => "X-Forwarded-User") do
      get root_path, headers: headers.merge("Remote-Email" => "uid_user2@example.com")
      assert User.find_by!(email: "uid_user2@example.com").identities.exists?(provider: "forward_auth", uid: "client_uid")
    end
  end

  # SA-04 review
  test "a client-added Remote-User cannot sign in as another user when only the email header is trusted" do
    victim = User.create!(email: "victim@example.com", password: "password123")
    victim.identities.create!(provider: "forward_auth", uid: "victim@example.com")
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1" ]
    io = StringIO.new
    capture = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(capture)

    # The operator listed Remote-User, but the proxy does not set or strip it.
    with_forward_auth_header_env("FORWARD_AUTH_EMAIL_HEADERS" => "X-Forwarded-Email", "FORWARD_AUTH_USER_HEADERS" => "Remote-User") do
      assert_no_difference [ "User.count", "Identity.count", "Session.count" ] do
        get root_path, headers: {
          "X-Forwarded-Email" => "attacker@example.com",
          "Remote-User" => "victim@example.com",
          "REMOTE_ADDR" => "127.0.0.1"
        }
      end
    end

    assert cookies[:session_token].blank?
    assert_not victim.sessions.exists?
    auth_lines = io.string.lines.grep(/\[auth\]/).join
    assert_includes auth_lines, "forward_auth_identity_email_mismatch"
    assert_not_includes auth_lines, "victim@example.com"
    assert_not_includes auth_lines, "attacker@example.com"
  ensure
    Rails.logger.stop_broadcasting_to(capture) if capture
  end

  # SA-04 review
  test "a returning forward-auth user whose email matches the identity still signs in" do
    user = User.create!(email: "regular@example.com", password: "password123")
    user.identities.create!(provider: "forward_auth", uid: "regular_uid")
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1" ]

    with_forward_auth_header_env("FORWARD_AUTH_USER_HEADERS" => "Remote-User") do
      assert_no_difference [ "User.count", "Identity.count" ] do
        get root_path, headers: {
          "Remote-Email" => "Regular@Example.com",
          "Remote-User" => "regular_uid",
          "REMOTE_ADDR" => "127.0.0.1"
        }
      end
    end

    assert cookies[:session_token].present?
    assert user.sessions.exists?
  end

  # SA-04 review round 2
  test "by default no user ID header is read, so a client-added Remote-User creates no identity with that uid" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1" ]

    with_forward_auth_header_env do
      get root_path, headers: {
        "Remote-Email" => "attacker@example.com",
        "Remote-User" => "victim@example.com",
        "REMOTE_ADDR" => "127.0.0.1"
      }
    end

    attacker = User.find_by!(email: "attacker@example.com")
    assert_equal [ "attacker@example.com" ], attacker.identities.where(provider: "forward_auth").pluck(:uid)
    assert_not Identity.exists?(provider: "forward_auth", uid: "victim@example.com")
  end

  # SA-04 review round 2
  test "the victim can still sign in after a client sent Remote-User with the victim's address" do
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1" ]

    with_forward_auth_header_env do
      get root_path, headers: { "Remote-Email" => "attacker@example.com", "Remote-User" => "victim@example.com", "REMOTE_ADDR" => "127.0.0.1" }
      cookies.delete("session_token")
      get root_path, headers: { "Remote-Email" => "victim@example.com", "REMOTE_ADDR" => "127.0.0.1" }
    end

    assert cookies[:session_token].present?
    assert User.find_by!(email: "victim@example.com").sessions.exists?
  end

  # SA-04 review round 2: what an Authelia install sees after upgrading without
  # setting FORWARD_AUTH_USER_HEADERS.
  test "an existing identity keyed by the old Remote-User default gets a second identity and the same account" do
    user = User.create!(email: "authelia_person@example.com", password: "password123")
    user.identities.create!(provider: "forward_auth", uid: "authelia_person")
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1" ]

    with_forward_auth_header_env do
      assert_no_difference "User.count" do
        assert_difference "Identity.count", 1 do
          get root_path, headers: {
            "Remote-Email" => "authelia_person@example.com",
            "Remote-User" => "authelia_person",
            "REMOTE_ADDR" => "127.0.0.1"
          }
        end
      end
    end

    assert user.sessions.exists?
    assert_equal %w[authelia_person authelia_person@example.com], user.identities.where(provider: "forward_auth").pluck(:uid).sort
  end

  # SA-04 review round 2
  test "the email in the mismatch check is compared without regard to case" do
    user = User.create!(email: "mixed@example.com", password: "password123")
    # The model normalizes email on write, so store the mixed case with raw SQL.
    User.where(id: user.id).update_all("email = 'Mixed@Example.com'")
    user.identities.create!(provider: "forward_auth", uid: "mixed_uid")
    FamilyPlates.config.forward_auth_enabled = true
    FamilyPlates.config.forward_auth_trusted_proxies = [ "127.0.0.1" ]

    with_forward_auth_header_env("FORWARD_AUTH_USER_HEADERS" => "Remote-User") do
      get root_path, headers: { "Remote-Email" => "MIXED@example.com", "Remote-User" => "mixed_uid", "REMOTE_ADDR" => "127.0.0.1" }
    end

    assert cookies[:session_token].present?
    assert user.sessions.exists?
  end

  private

  # Runs the block with the forward-auth header variables cleared, then set to
  # the given values, and restores whatever they were.
  def with_forward_auth_header_env(overrides = {})
    keys = %w[FORWARD_AUTH_EMAIL_HEADERS FORWARD_AUTH_EMAIL_HEADER FORWARD_AUTH_USER_HEADERS
              FORWARD_AUTH_USER_HEADER FORWARD_AUTH_NAME_HEADERS FORWARD_AUTH_NAME_HEADER]
    original = keys.to_h { |key| [ key, ENV[key] ] }
    keys.each { |key| ENV.delete(key) }
    overrides.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
