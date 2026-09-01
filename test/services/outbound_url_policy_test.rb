require "test_helper"

# Recipe import passes a user-supplied URL straight to an HTTP client, so this
# policy is the only thing standing between "paste a recipe link" and "make this
# server fetch whatever I want from inside its own network".
class OutboundUrlPolicyTest < ActiveSupport::TestCase
  def assert_rejected(url, matching: nil)
    error = assert_raises(OutboundUrlPolicy::Rejected, "#{url} should have been refused") do
      OutboundUrlPolicy.check!(url)
    end
    assert_match(matching, error.message) if matching
    error
  end

  # minitest/mock is not available here, and a policy that decides by resolved
  # address needs its resolver swapped to test split answers without real DNS.
  def with_resolved_addresses(addresses)
    original = OutboundUrlPolicy.method(:resolve)
    OutboundUrlPolicy.define_singleton_method(:resolve) { |_host| addresses }
    yield
  ensure
    OutboundUrlPolicy.define_singleton_method(:resolve, original)
  end

  test "refuses every scheme but http and https" do
    # file: is not actually reachable through open-uri (URI::File has no #open),
    # but ftp: is - URI::FTP includes OpenURI::OpenRead - so the allowlist is
    # what closes it, not the accident of which classes got the mixin.
    assert_rejected "file:///etc/passwd", matching: /scheme/
    assert_rejected "ftp://example.com/secrets", matching: /scheme/
    assert_rejected "gopher://example.com/", matching: /scheme/
    assert_rejected "data:text/html,hello", matching: /scheme/
  end

  test "refuses loopback in every spelling" do
    assert_rejected "http://127.0.0.1/"
    assert_rejected "http://127.0.0.1:3000/admin"
    assert_rejected "http://127.1.2.3/", matching: /global unicast/
    assert_rejected "http://[::1]/"
    assert_rejected "http://localhost:3000/"
  end

  test "refuses private and shared address space" do
    assert_rejected "http://10.0.0.1/"
    assert_rejected "http://172.16.0.1/"
    assert_rejected "http://172.31.255.254/"
    assert_rejected "http://192.168.1.1/"
    assert_rejected "http://100.64.0.1/"
    assert_rejected "http://[fc00::1]/"
    assert_rejected "http://[fd12:3456::1]/"
  end

  test "refuses the cloud metadata service" do
    assert_rejected "http://169.254.169.254/latest/meta-data/"
    assert_rejected "http://[fe80::1]/"
  end

  test "refuses unspecified, multicast and reserved space" do
    assert_rejected "http://0.0.0.0/"
    assert_rejected "http://224.0.0.1/"
    assert_rejected "http://255.255.255.255/"
    assert_rejected "http://[::]/"
    assert_rejected "http://[ff02::1]/"
  end

  test "refuses IPv4-mapped IPv6 spellings of blocked addresses" do
    assert_rejected "http://[::ffff:127.0.0.1]/"
    assert_rejected "http://[::ffff:169.254.169.254]/"
    assert_rejected "http://[::ffff:10.0.0.1]/"
  end

  test "refuses a URL with no host" do
    assert_rejected "http:///etc/passwd"
    assert_rejected "/etc/passwd", matching: /scheme/
  end

  test "refuses a URL it cannot parse rather than guessing" do
    assert_rejected "http://exa mple.com/<script>", matching: /unparseable/
  end

  test "allows an ordinary public address and pins it" do
    target = OutboundUrlPolicy.check!("https://93.184.216.34/recipes/pie")

    assert_equal "93.184.216.34", target.address
    assert_equal "https", target.uri.scheme
    assert_equal "/recipes/pie", target.uri.path
  end

  test "rejects a host when any of its answers is blocked" do
    with_resolved_addresses([ "93.184.216.34", "127.0.0.1" ]) do
      assert_rejected "http://split-horizon.test/", matching: /127\.0\.0\.1/
    end
  end

  test "pins the resolved address so it cannot be re-resolved later" do
    with_resolved_addresses([ "93.184.216.34" ]) do
      target = OutboundUrlPolicy.check!("https://recipes.test/x")

      assert_equal "93.184.216.34", target.address
      assert_equal "recipes.test", target.uri.host, "the hostname is kept for SNI and Host"
    end
  end
end
