require "test_helper"

class LogPathFilterTest < ActionDispatch::IntegrationTest
  def capture_log
    log = StringIO.new
    capture = ActiveSupport::Logger.new(log, level: :debug)
    Rails.logger.broadcast_to(capture)
    yield
    log.string
  ensure
    Rails.logger.stop_broadcasting_to(capture) if capture
  end

  test "calendar feed requests keep working but never log the token" do
    household = households(:one)
    token = household.calendar_feed_token

    output = capture_log do
      get calendar_feed_url(token: token, format: :ics)
      assert_response :success
      assert_includes response.body, "BEGIN:VCALENDAR"
    end

    assert_includes output, "Started GET"
    assert_includes output, "/calendars/feed/[FILTERED]"
    assert_not_includes output, token
  end

  test "member calendar feed does not log the token" do
    household = households(:one)
    token = household.calendar_feed_token

    output = capture_log do
      get calendar_member_feed_url(token: token, member_id: family_members(:one).id, format: :ics)
      assert_response :success
    end

    assert_not_includes output, token
  end

  test "transfer links keep working but never log the token" do
    member = family_members(:one)
    token = member.transfer_id

    output = capture_log do
      get transfer_path(token: token)
      assert_response :success
      assert_select "h1", text: /Claim Profile: #{member.name}/
    end

    assert_includes output, "/transfer/[FILTERED]"
    assert_not_includes output, token
  end

  test "filter leaves other paths alone" do
    assert_equal "/recipes/1", LogPathFilter.filter("/recipes/1")
    assert_equal "/calendars/feed/[FILTERED]/members/3", LogPathFilter.filter("/calendars/feed/abc123/members/3")
  end

  test "redact finds a token anywhere in a message, however its separators are written" do
    token = "feedtoken-RED-012"

    assert_equal "GET /transfer/[FILTERED] 200", LogPathFilter.redact("GET /transfer/#{token} 200")
    assert_equal "/calendars/feed/[FILTERED]/members/42", LogPathFilter.redact("/calendars/feed/#{token}/members/42")
    assert_equal "feed_token=[FILTERED]&calendar_token=[FILTERED]&page=2",
      LogPathFilter.redact("feed_token=#{token}&calendar_token=#{token}&page=2")
    assert_not_includes LogPathFilter.redact("/calendars/feed/#{token}".gsub("/", "\\/")), token
    assert_not_includes LogPathFilter.redact("GET /transfer%2F#{token} 200"), token
    assert_equal "/recipes/12?page=2", LogPathFilter.redact("/recipes/12?page=2")
  end

  test "a Rails log line is redacted by the formatter, token and all" do
    token = "feedtoken-RED-012"
    formatter = ActiveSupport::Logger::SimpleFormatter.new
    formatter.extend(LogPathFilter::RedactingFormatter)

    line = formatter.call("ERROR", Time.now, nil, "ActionController::RoutingError (No route matches /calendars/feed/#{token}/bad)")
    assert_not_includes line, token
    assert_includes line, "/calendars/feed/[FILTERED]/bad"

    logger = ActiveSupport::Logger.new(io = StringIO.new)
    logger.formatter = ActiveSupport::Logger::SimpleFormatter.new
    LogPathFilter.install(logger)
    logger.error("boom on /transfer/#{token}?token=#{token}")
    assert_not_includes io.string, token
  end
end
