require "test_helper"

class CalendarFeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @member = family_members(:one)
    @token = @household.calendar_feed_token
    @meal_plan = @household.current_meal_plan(Date.current.beginning_of_week)

    @slot = @meal_plan.meal_plan_slots.create!(
      date: Date.current,
      meal_type: "dinner",
      custom_title: "Tacos",
      family_member: @member
    )
  end

  test "renders household calendar feed with valid token without authentication" do
    get calendar_feed_url(token: @token, format: :ics)

    assert_response :success
    assert_equal "text/calendar; charset=utf-8", response.content_type
    assert_includes response.headers["Content-Disposition"], "inline; filename=\"familyplates-#{@household.name.parameterize}.ics\""

    assert_includes response.body, "BEGIN:VCALENDAR"
    assert_includes response.body, "X-WR-CALNAME:FamilyPlates - #{@household.name}"
    assert_includes response.body, "SUMMARY:🍽️ Dinner: Tacos (Cook: #{@member.name})"
    assert_includes response.body, "END:VCALENDAR"
  end

  test "renders member-filtered calendar feed" do
    get calendar_member_feed_url(token: @token, member_id: @member.id, format: :ics)

    assert_response :success
    assert_equal "text/calendar; charset=utf-8", response.content_type
    assert_includes response.headers["Content-Disposition"], "inline; filename=\"familyplates-#{@member.name.parameterize}-cooking.ics\""
    assert_includes response.body, "X-WR-CALNAME:FamilyPlates - #{@member.name}'s Cooking"
    assert_includes response.body, "SUMMARY:🍽️ Dinner: Tacos (Cook: #{@member.name})"
  end

  test "returns 404 for invalid token" do
    get calendar_feed_url(token: "invalid_random_token_12345", format: :ics)

    assert_response :not_found
  end

  test "returns 404 for invalid member id in member feed" do
    get calendar_member_feed_url(token: @token, member_id: "non-existent-member-id", format: :ics)

    assert_response :not_found
  end

  test "returns 304 Not Modified when ETag matches" do
    get calendar_feed_url(token: @token, format: :ics)
    assert_response :success

    etag = response.headers["ETag"]
    assert etag.present?, "Response must set ETag"

    get calendar_feed_url(token: @token, format: :ics), headers: { "HTTP_IF_NONE_MATCH" => etag }
    assert_response :not_modified
    assert_empty response.body
  end

  test "renders calendar feed with external calendar agent user agent" do
    get calendar_feed_url(token: @token, format: :ics), headers: { "HTTP_USER_AGENT" => "Mac_OS_X/14.0 (23A344) CalendarAgent/954" }

    assert_response :success
    assert_includes response.body, "BEGIN:VCALENDAR"
  end
end
