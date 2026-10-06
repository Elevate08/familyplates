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

  test "the mode comes from the configured edition and TRUSTED_PROXIES from the environment" do
    FamilyPlates.config.mode = "appliance"
    ENV["TRUSTED_PROXIES"] = "172.18.0.5"

    assert_includes FamilyPlates.trusted_proxies, IPAddr.new("172.18.0.5")
  ensure
    ENV.delete("TRUSTED_PROXIES")
    FamilyPlates.config.reset!
  end
end
