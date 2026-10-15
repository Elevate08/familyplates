require "test_helper"

# SA-09: Rails trusts every private range as a proxy, so on an appliance a LAN
# client could name any address it liked in X-Forwarded-For. An appliance now
# trusts loopback (Thruster) and the single addresses listed in TRUSTED_PROXIES.
# The hosted edition keeps Rails' default: its clients arrive from public
# addresses through kamal-proxy on a private network.
class TrustedProxiesTest < ActiveSupport::TestCase
  APP = ->(env) { [ 200, {}, [ ActionDispatch::Request.new(env).remote_ip.to_s ] ] }

  def remote_ip_for(proxies, remote_addr:, forwarded_for: nil)
    env = Rack::MockRequest.env_for("/", "REMOTE_ADDR" => remote_addr)
    env["HTTP_X_FORWARDED_FOR"] = forwarded_for if forwarded_for
    _status, _headers, body = ActionDispatch::RemoteIp.new(APP, true, proxies).call(env)
    body.first
  end

  def appliance_proxies(extra = nil)
    FamilyPlates.trusted_proxies(hosted: false, extra: extra)
  end

  test "an appliance behind Thruster records the address Thruster saw, not a spoofed first entry" do
    assert_equal "192.168.1.50",
      remote_ip_for(appliance_proxies, remote_addr: "127.0.0.1", forwarded_for: "203.0.113.50, 192.168.1.50")
  end

  test "an appliance with no X-Forwarded-For uses the connecting address" do
    assert_equal "127.0.0.1", remote_ip_for(appliance_proxies, remote_addr: "127.0.0.1")
  end

  test "an appliance trusts IPv6 loopback" do
    assert_equal "192.168.1.50",
      remote_ip_for(appliance_proxies, remote_addr: "::1", forwarded_for: "203.0.113.50, 192.168.1.50")
  end

  test "TRUSTED_PROXIES adds a reverse proxy's address, so its client is recorded" do
    proxies = appliance_proxies("172.18.0.5")

    # Thruster appended the proxy container it saw; the proxy appended the real client.
    assert_equal "198.51.100.7",
      remote_ip_for(proxies, remote_addr: "127.0.0.1", forwarded_for: "203.0.113.50, 198.51.100.7, 172.18.0.5")
  end

  test "without TRUSTED_PROXIES a reverse proxy's address is the client address" do
    assert_equal "172.18.0.5",
      remote_ip_for(appliance_proxies, remote_addr: "127.0.0.1", forwarded_for: "198.51.100.7, 172.18.0.5")
  end

  test "TRUSTED_PROXIES takes a comma-separated list and ignores blanks and spaces" do
    proxies = appliance_proxies(" 172.18.0.5 , ,fd00::5")

    assert_equal [ "127.0.0.0/8", "::1", "172.18.0.5", "fd00::5" ].map { IPAddr.new(_1) }, proxies
  end

  test "TRUSTED_PROXIES refuses a range, which would trust every client in it" do
    error = assert_raises(ArgumentError) { appliance_proxies("10.0.0.0/8") }

    assert_includes error.message, "TRUSTED_PROXIES"
    assert_includes error.message, "10.0.0.0/8"
  end

  test "TRUSTED_PROXIES refuses an entry that is not an address" do
    error = assert_raises(ArgumentError) { appliance_proxies("proxy.example.com") }

    assert_includes error.message, "proxy.example.com"
  end

  test "the hosted edition keeps Rails' default trusted proxies" do
    assert_nil FamilyPlates.trusted_proxies(hosted: true, extra: "172.18.0.5")
  end

  test "hosted clients behind kamal-proxy still get their own address" do
    # nil: the middleware falls back to Rails' default list, as in production.
    assert_equal "198.51.100.7", remote_ip_for(nil, remote_addr: "172.18.0.2", forwarded_for: "198.51.100.7")
  end

  test "TRUSTED_PROXIES matches an IPv4-mapped IPv6 address, as forward-auth's list does" do
    proxies = appliance_proxies("::ffff:172.18.0.5")

    assert_includes proxies, IPAddr.new("172.18.0.5")
    assert_equal "198.51.100.7",
      remote_ip_for(proxies, remote_addr: "127.0.0.1", forwarded_for: "198.51.100.7, 172.18.0.5")
  end

  test "TRUSTED_PROXIES refuses a mapped range" do
    assert_raises(ArgumentError) { appliance_proxies("::ffff:172.18.0.0/112") }
  end

  test "single_ip returns one address, with an IPv4-mapped one as IPv4" do
    assert_equal IPAddr.new("172.18.0.5"), FamilyPlates.single_ip(" 172.18.0.5 ")
    assert_equal IPAddr.new("172.18.0.5"), FamilyPlates.single_ip("::ffff:172.18.0.5")
    assert_equal IPAddr.new("172.18.0.5"), FamilyPlates.single_ip("172.18.0.5/32")
    assert_equal IPAddr.new("fd00::5"), FamilyPlates.single_ip("fd00::5/128")
  end

  test "single_ip tells a range from something that is not an address" do
    assert_raises(IPAddr::InvalidPrefixError) { FamilyPlates.single_ip("10.0.0.0/8") }
    assert_raises(IPAddr::InvalidPrefixError) { FamilyPlates.single_ip("::ffff:10.0.0.0/104") }
    assert_raises(IPAddr::InvalidAddressError) { FamilyPlates.single_ip("proxy.example.com") }
    assert_raises(IPAddr::InvalidAddressError) { FamilyPlates.single_ip("") }
  end

  # An appliance that was already behind a reverse proxy, with TRUSTED_PROXIES not
  # set yet, would otherwise record every client as the proxy's address and share
  # one per-IP sign-in and PIN allowance. With forward-auth on, its setting names
  # the proxy.
  def with_forward_auth(enabled, proxies)
    FamilyPlates.config.forward_auth_enabled = enabled
    FamilyPlates.config.forward_auth_trusted_proxies = proxies
    yield
  ensure
    FamilyPlates.config.reset!
  end

  test "with TRUSTED_PROXIES unset and forward-auth on, the forward-auth proxy addresses are trusted too" do
    with_forward_auth(true, [ "172.18.0.5" ]) do
      [ nil, "", " , ", "," ].each do |unset|
        proxies = FamilyPlates.trusted_proxies(hosted: false, extra: unset)

        assert_equal "198.51.100.7",
          remote_ip_for(proxies, remote_addr: "127.0.0.1", forwarded_for: "203.0.113.50, 198.51.100.7, 172.18.0.5"),
          "TRUSTED_PROXIES #{unset.inspect}"
      end
    end
  end

  test "with forward-auth off, its proxy addresses are not trusted to set the client address" do
    with_forward_auth(false, [ "172.17.0.1" ]) do
      proxies = FamilyPlates.trusted_proxies(hosted: false, extra: nil)

      assert_equal [ "127.0.0.0/8", "::1" ].map { IPAddr.new(_1) }, proxies
      assert_equal "172.17.0.1",
        remote_ip_for(proxies, remote_addr: "127.0.0.1", forwarded_for: "203.0.113.50, 172.17.0.1")
    end
  end

  test "a set TRUSTED_PROXIES replaces the forward-auth fallback" do
    with_forward_auth(true, [ "172.18.0.5" ]) do
      proxies = FamilyPlates.trusted_proxies(hosted: false, extra: "172.18.0.9")

      assert_includes proxies, IPAddr.new("172.18.0.9")
      assert_not_includes proxies, IPAddr.new("172.18.0.5")
    end
  end

  test "the fallback leaves out forward-auth ranges and non-addresses" do
    with_forward_auth(true, [ "172.18.0.5", "10.0.0.0/8", "traefik", "::ffff:172.18.0.6" ]) do
      assert_equal [ "127.0.0.0/8", "::1", "172.18.0.5", "172.18.0.6" ].map { IPAddr.new(_1) },
        FamilyPlates.trusted_proxies(hosted: false, extra: nil)
    end
  end

  test "the hosted edition keeps Rails' default whatever TRUSTED_PROXIES says" do
    skip "hosted mode needs the hosted bundle" unless FamilyPlates.saas?

    previous = ENV["TRUSTED_PROXIES"]
    FamilyPlates.config.mode = "hosted"
    ENV["TRUSTED_PROXIES"] = "172.18.0.5"

    assert_predicate FamilyPlates.config, :hosted?
    assert_nil FamilyPlates.trusted_proxies
  ensure
    previous.nil? ? ENV.delete("TRUSTED_PROXIES") : ENV["TRUSTED_PROXIES"] = previous
    FamilyPlates.config.reset!
  end

  test "the appliance mode comes from the configured edition and TRUSTED_PROXIES from the environment" do
    previous = ENV["TRUSTED_PROXIES"]
    FamilyPlates.config.mode = "appliance"
    ENV["TRUSTED_PROXIES"] = "172.18.0.5"

    assert_includes FamilyPlates.trusted_proxies, IPAddr.new("172.18.0.5")
  ensure
    previous.nil? ? ENV.delete("TRUSTED_PROXIES") : ENV["TRUSTED_PROXIES"] = previous
    FamilyPlates.config.reset!
  end

  # Narrowing the trusted list only helps requests that arrive through Thruster.
  # Puma must not be reachable on its own port from outside the container, or a
  # client could send a forged X-Forwarded-For straight to it. Thruster (the
  # image's CMD, and what kamal-proxy and the published port reach) talks to it
  # over loopback.
  test "the image binds Puma to loopback and starts it behind Thruster" do
    dockerfile = Rails.root.join("Dockerfile").read

    assert_match(/^ENV .*\bBINDING="?127\.0\.0\.1"?/m, dockerfile.gsub(/\\\n\s*/, " "))
    assert_match(/^CMD \["\.\/bin\/thrust", "\.\/bin\/rails", "server"\]$/, dockerfile)
  end

  # Starting Puma straight from config/puma.rb must bind the way `rails server`
  # does, from the same BINDING setting.
  def puma_binds(binding_env)
    require "puma/configuration"
    previous = ENV["BINDING"]
    binding_env.nil? ? ENV.delete("BINDING") : ENV["BINDING"] = binding_env
    config = Puma::Configuration.new({ config_files: [ Rails.root.join("config/puma.rb").to_s ] })
    config.clamp
    config.final_options[:binds]
  ensure
    previous.nil? ? ENV.delete("BINDING") : ENV["BINDING"] = previous
  end

  test "puma.rb binds to BINDING when it is set" do
    assert_equal [ "tcp://127.0.0.1:3000" ], puma_binds("127.0.0.1")
  end

  test "puma.rb binds as before when BINDING is unset or blank" do
    # Puma's own default host (all addresses), the same as a bare `port 3000`.
    [ nil, "" ].each do |unset|
      binds = puma_binds(unset)

      assert_equal 1, binds.size
      assert_match(%r{\Atcp://(0\.0\.0\.0|\[::\]):3000\z}, binds.first, "BINDING #{unset.inspect}")
    end
  end
end
