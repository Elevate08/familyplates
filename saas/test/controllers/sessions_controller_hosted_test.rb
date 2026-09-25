require "test_helper"

class SessionsControllerHostedTest < ActionDispatch::IntegrationTest
  setup do
    FamilyPlates.config.reset!
  end

  teardown do
    FamilyPlates.config.reset!
  end

  # @card-15.9
  test "a hosted sign-in code never reaches the log, even at debug level" do
    FamilyPlates.config.mode = "hosted"
    User.create!(email: "hosted@example.com")
    log = StringIO.new
    # Debug is the level at which Rails would log the whole email.
    capture = ActiveSupport::Logger.new(log, level: :debug)
    Rails.logger.broadcast_to(capture)

    perform_enqueued_jobs do
      post session_path, params: { email: "hosted@example.com" }
    end
    code = MagicCode.last.code
    post verify_session_path, params: { email: "hosted@example.com", code: code }

    assert_redirected_to root_url
    assert_match "Delivered mail", log.string, "the capture should see the mailer's own log line"
    assert_no_match code, log.string
  ensure
    Rails.logger.stop_broadcasting_to(capture) if capture
  end

  # @card-15.4
  test "hosted mode flow is identical for unknown email (enumeration-safe)" do
    FamilyPlates.config.mode = "hosted"

    assert_no_emails do
      post session_path, params: { email: "stranger@example.com" }
    end

    assert_redirected_to verify_session_path
    assert_equal "If an account exists for that email, a 6-character code has been sent.", flash[:notice]
    assert_equal 0, MagicCode.where(email: "stranger@example.com").count
  end

  # @card-15.5
  test "hosted mode rejects expired or invalid magic code with generic error" do
    FamilyPlates.config.mode = "hosted"
    user = User.create!(email: "hosted@example.com")
    user.magic_codes.create!(email: user.email, code: "ABC123", expires_at: 1.minute.ago)

    post verify_session_path, params: { email: user.email, code: "ABC123" }
    assert_response :unprocessable_entity
    assert_equal "Invalid or expired code.", flash[:alert]

    post verify_session_path, params: { email: user.email, code: "WRONG1" }
    assert_response :unprocessable_entity
    assert_equal "Invalid or expired code.", flash[:alert]
  end

  # @card-15.3
  test "hosted mode renders hosted sign-in and sends 6-character code" do
    FamilyPlates.config.mode = "hosted"
    user = User.create!(email: "hosted@example.com")

    get new_session_path
    assert_response :success
    assert_select "h1", text: /Sign in to FamilyPlates/i

    assert_enqueued_emails 1 do
      post session_path, params: { email: "hosted@example.com" }
    end

    assert_redirected_to verify_session_path
    magic_code = user.magic_codes.last
    assert_not_nil magic_code
    assert_match(/\A[A-Z0-9]{6}\z/, magic_code.code)
    assert magic_code.expires_at > Time.current
  end

  # @card-15.5
  test "hosted mode verifies valid magic code, single-use destruction, and creates session" do
    FamilyPlates.config.mode = "hosted"
    user = User.create!(email: "hosted@example.com")
    magic_code = user.magic_codes.create!(email: user.email, code: "ABC123", expires_at: 15.minutes.from_now)

    post verify_session_path, params: { email: user.email, code: "abc123" }

    assert_redirected_to root_url
    assert cookies[:session_token].present?
    assert_not MagicCode.exists?(magic_code.id)
  end
end
