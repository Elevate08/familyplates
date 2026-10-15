require "test_helper"

class StagingAccessGateTest < ActiveSupport::TestCase
  setup do
    @app = ->(_env) { [ 200, {}, [ "app" ] ] }
    @gate = FamilyPlatesSaas::StagingAccessGate.new(@app, "tester", "placeholder-password")
  end

  test "the UI is closed without staging credentials" do
    [ [ "GET", "/" ], [ "GET", "/signup" ], [ "GET", "/platform_admin/session/new" ], [ "POST", "/session" ],
      [ "GET", "/pay/payments/pi_123" ] ].each do |method, path|
      status, headers, = @gate.call(request(method, path))
      assert_equal 401, status, "#{method} #{path}"
      assert_match(/\ABasic realm=/, headers["www-authenticate"])
    end
  end

  test "Stripe's signed test webhook reaches the app with no credentials" do
    assert_equal 200, @gate.call(request("POST", "/pay/webhooks/stripe")).first
  end

  test "only the webhook's POST is open, not the path" do
    assert_equal 401, @gate.call(request("GET", "/pay/webhooks/stripe")).first
    assert_equal 401, @gate.call(request("POST", "/pay/webhooks/stripe/../../signup")).first
    assert_equal 401, @gate.call(request("POST", "/pay/webhooks/other")).first
  end

  test "the health check stays open for kamal-proxy" do
    assert_equal 200, @gate.call(request("GET", "/up")).first
  end

  test "the right credentials open the app and wrong ones do not" do
    assert_equal 200, @gate.call(request("GET", "/", basic("tester", "placeholder-password"))).first
    assert_equal 401, @gate.call(request("GET", "/", basic("tester", "wrong"))).first
    assert_equal 401, @gate.call(request("GET", "/", basic("other", "placeholder-password"))).first
  end

  test "blank configured credentials never open the gate" do
    gate = FamilyPlatesSaas::StagingAccessGate.new(@app, "", nil)
    assert_equal 401, gate.call(request("GET", "/", basic("", ""))).first
  end

  private

  def request(method, path, headers = {})
    Rack::MockRequest.env_for(path, { method: method }.merge(headers))
  end

  def basic(username, password)
    { "HTTP_AUTHORIZATION" => "Basic #{[ "#{username}:#{password}" ].pack("m0")}" }
  end
end
