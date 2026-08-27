require "test_helper"

class FeedsControllerTest < ActionDispatch::IntegrationTest
  test "should serve ics feed with valid token without login" do
    household = households(:one)
    get calendar_feed_url(household.calendar_token)

    assert_response :success
    assert_equal "text/calendar; charset=utf-8", response.media_type + "; charset=" + response.charset
    assert_includes response.body, "BEGIN:VCALENDAR"
    assert_includes response.body, "Taco Tuesday"
  end

  test "should return 404 for invalid token" do
    get calendar_feed_url("nonexistent-token-123")
    assert_response :not_found
  end
end
