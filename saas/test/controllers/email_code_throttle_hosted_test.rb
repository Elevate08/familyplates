require "test_helper"

class EmailCodeThrottleHostedTest < ActionDispatch::IntegrationTest
  setup do
    FamilyPlates.config.reset!
    FamilyPlates.config.mode = "hosted"
    @user = User.create!(email: "victim-code@example.com")
  end

  teardown do
    FamilyPlates.config.reset!
  end

  test "guessing without an email param across IPs cannot redeem a code" do
    post session_path, params: { email: @user.email }
    real = MagicCode.find_by!(email: @user.email).code

    # No :email param, so only session[:pending_auth_email] identifies the address.
    6.times do |i|
      post verify_session_path, params: { code: "WRONG#{i}" }, headers: { "REMOTE_ADDR" => "203.0.113.#{i + 1}" }
    end

    assert_equal 0, MagicCode.where(email: @user.email).count, "active codes must be destroyed after repeated failures"

    post verify_session_path, params: { code: real }, headers: { "REMOTE_ADDR" => "203.0.113.99" }
    assert_nil cookies[:session_token].presence

    # Guessing cannot lock the person out: a code they request afterwards works.
    post session_path, params: { email: @user.email }
    later = MagicCode.find_by!(email: @user.email).code
    post verify_session_path, params: { code: later }, headers: { "REMOTE_ADDR" => "203.0.113.100" }
    assert cookies[:session_token].present?
  end

  test "a new code replaces the previous one" do
    post session_path, params: { email: @user.email }
    first = MagicCode.find_by!(email: @user.email).code
    post session_path, params: { email: @user.email }

    assert_equal 1, MagicCode.where(email: @user.email).count
    post verify_session_path, params: { code: first }
    assert_response :unprocessable_entity
  end
end
