require "test_helper"

class DeviceGrantTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "parent@example.com", password: "password123")
    @household = households(:one)
  end

  test "creates grant with RFC 8628 defaults" do
    grant = DeviceGrant.create!(ip_address: "127.0.0.1", user_agent: "TestBrowser/1.0")

    assert grant.device_code.present?
    assert_equal 64, grant.device_code.length # 32 bytes hex
    assert grant.user_code.present?
    assert_match(/\A[2345679ACDEFGHJKMNPQRTUVWXYZ]{4}-[2345679ACDEFGHJKMNPQRTUVWXYZ]{4}\z/, grant.user_code)
    assert_equal "kiosk", grant.kind
    assert_equal "pending", grant.status
    assert grant.pending?
    assert_not grant.expired?
    assert_not grant.approved?
    assert_not grant.denied?
    assert_in_delta 15.minutes.from_now, grant.expires_at, 5.seconds
    assert_equal 5, grant.interval_seconds
  end

  test "normalizes and finds grant by user code in various formats" do
    grant = DeviceGrant.create!
    raw_code = grant.user_code # e.g. ABCD-EFGH

    assert_equal grant, DeviceGrant.find_by_user_code(raw_code)
    assert_equal grant, DeviceGrant.find_by_user_code(raw_code.downcase)
    assert_equal grant, DeviceGrant.find_by_user_code(raw_code.delete("-"))
    assert_equal grant, DeviceGrant.find_by_user_code("  #{raw_code.downcase}  ")
    assert_nil DeviceGrant.find_by_user_code("NONEXISTENT")
    assert_nil DeviceGrant.find_by_user_code("")
    assert_nil DeviceGrant.find_by_user_code(nil)
  end

  test "reports expired? when past expires_at" do
    grant = DeviceGrant.create!(expires_at: 1.minute.ago)
    assert grant.expired?
    assert_not grant.pending?
    assert_equal 0, grant.expires_in_seconds
  end

  test "approves grant and creates non-expiring kiosk session" do
    grant = DeviceGrant.create!(kind: "kiosk", ip_address: "10.0.0.1", user_agent: "WallTablet/1.0")

    assert_difference -> { @user.sessions.count } => 1 do
      grant.approve!(by: @user, household: @household, kind: "kiosk")
    end

    assert grant.reload.approved?
    assert_not grant.pending?
    assert_equal "approved", grant.status
    assert_equal @user, grant.user
    assert_equal @household, grant.household
    assert grant.session.present?
    assert_equal "kiosk", grant.session.kind
    assert grant.session.kiosk?
    assert_not grant.session.expired?
    assert_equal "10.0.0.1", grant.session.ip_address
    assert_equal "WallTablet/1.0", grant.session.user_agent
  end

  test "approves grant as browser session for laptop sign-in" do
    grant = DeviceGrant.create!(kind: "browser", ip_address: "192.168.1.100", user_agent: "Laptop/1.0")

    grant.approve!(by: @user, household: @household, kind: "browser")

    assert grant.approved?
    assert_equal "browser", grant.session.kind
    assert grant.session.browser?
  end

  test "cannot approve an already approved or expired grant" do
    grant = DeviceGrant.create!(expires_at: 1.minute.ago)
    assert_raises(RuntimeError) do
      grant.approve!(by: @user, household: @household)
    end
  end

  test "denies grant" do
    grant = DeviceGrant.create!
    grant.deny!

    assert grant.denied?
    assert_not grant.pending?
    assert_equal "denied", grant.status
  end

  test "detects polling too fast according to interval" do
    grant = DeviceGrant.create!
    assert_not grant.polling_too_fast?

    grant.update_columns(last_polled_at: Time.current)
    assert grant.polling_too_fast?

    grant.update_columns(last_polled_at: 6.seconds.ago)
    assert_not grant.polling_too_fast?
  end
end
