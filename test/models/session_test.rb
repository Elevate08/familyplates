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
end
