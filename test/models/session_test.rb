require "test_helper"

class SessionTest < ActiveSupport::TestCase
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  test "assigns a UUID and defaults to a browser session" do
    user = User.create!(email: "parent@example.com")
    session = user.sessions.create!(token: "session-token", last_active_at: Time.current)

    assert_match UUID_PATTERN, session.id
    assert_equal "browser", session.kind
    assert_nil session.expires_at
  end

  test "expires after 30 days of inactivity" do
    user = User.create!(email: "parent@example.com")
    session = user.sessions.create!(token: "token-1", last_active_at: 31.days.ago)

    assert session.expired?
    assert session.idle_expired?
  end

  test "expires after 90 days absolute duration" do
    user = User.create!(email: "parent@example.com")
    session = user.sessions.create!(token: "token-2", created_at: 91.days.ago, last_active_at: 1.hour.ago)

    assert session.expired?
    assert session.absolute_expired?
  end

  test "kiosk sessions do not expire" do
    user = User.create!(email: "parent@example.com")
    session = user.sessions.create!(token: "token-3", kind: "kiosk", created_at: 100.days.ago, last_active_at: 40.days.ago)

    assert_not session.expired?
  end

  test "resume throttles database writes to at most once per hour" do
    user = User.create!(email: "parent@example.com")
    session = user.sessions.create!(token: "token-4", last_active_at: 10.minutes.ago)

    assert_no_changes -> { session.reload.last_active_at } do
      session.resume(user_agent: "Firefox", ip_address: "1.2.3.4")
    end

    session.update_columns(last_active_at: 65.minutes.ago)
    session.resume(user_agent: "Chrome", ip_address: "5.6.7.8")

    session.reload
    assert_equal "Chrome", session.user_agent
    assert_equal "5.6.7.8", session.ip_address
    assert session.last_active_at > 1.minute.ago
  end
end
