require "test_helper"

class CalendarFeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @member = family_members(:one)
    @token = @household.calendar_feed_token
    @meal_plan = @household.current_meal_plan(Date.current.beginning_of_week)
    # The meal_plan_slots fixtures sit in the current week, so on some weekday
    # one of them is "today" and collides with the slots these tests plan by the
    # clock. Start from an empty plan so the result never depends on the weekday.
    MealPlanSlot.where(meal_plan: @household.meal_plans).delete_all

    @slot = @meal_plan.meal_plan_slots.create!(
      date: Date.current,
      meal_type: "dinner",
      custom_title: "Tacos",
      family_member: @member
    )
  end

  # @card-39.1
  test "renders household calendar feed with valid token without authentication" do
    get calendar_feed_url(token: @token, format: :ics)

    assert_response :success
    assert_equal "text/calendar; charset=utf-8", response.content_type
    assert_includes response.headers["Content-Disposition"], "inline; filename=\"familyplates-#{@household.name.parameterize}.ics\""

    assert_includes response.body, "BEGIN:VCALENDAR"
    assert_includes response.body, "X-WR-CALNAME:FamilyPlates - #{@household.name}"
    assert_includes response.body, "SUMMARY:🍽️ Dinner: Tacos (Cook: #{@member.name})"
    assert_includes response.body, "END:VCALENDAR"
    assert_not_includes response.headers["Cache-Control"].to_s, "public"
  end

  # @card-38.4
  test "renders member-filtered calendar feed" do
    get calendar_member_feed_url(token: @token, member_id: @member.id, format: :ics)

    assert_response :success
    assert_equal "text/calendar; charset=utf-8", response.content_type
    assert_includes response.headers["Content-Disposition"], "inline; filename=\"familyplates-#{@member.name.parameterize}-cooking.ics\""
    assert_includes response.body, "X-WR-CALNAME:FamilyPlates - #{@member.name}'s Cooking"
    assert_includes response.body, "SUMMARY:🍽️ Dinner: Tacos (Cook: #{@member.name})"
  end

  # @card-39.1
  test "returns 404 for invalid token" do
    get calendar_feed_url(token: "invalid_random_token_12345", format: :ics)

    assert_response :not_found
  end

  # @card-39.1
  test "returns 404 for invalid member id in member feed" do
    get calendar_member_feed_url(token: @token, member_id: "non-existent-member-id", format: :ics)

    assert_response :not_found
  end

  # @card-39.2
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

  # @card-39.2
  test "ETag changes when a slot is deleted or a recipe is renamed" do
    recipe = @household.recipes.create!(title: "Feed Pasta", instructions: "1. Boil.")
    older = @meal_plan.meal_plan_slots.create!(date: Date.current, meal_type: "lunch", recipe: recipe)
    older.update_columns(updated_at: 2.days.ago)

    get calendar_feed_url(token: @token, format: :ics)
    first_etag = response.headers["ETag"]

    older.delete
    get calendar_feed_url(token: @token, format: :ics), headers: { "HTTP_IF_NONE_MATCH" => first_etag }
    assert_response :success, "deleting a slot that was not the latest edit must invalidate the feed"
    second_etag = response.headers["ETag"]

    @household.recipes.where.not(id: recipe.id).update_all(updated_at: 3.days.ago)
    recipe.update!(title: "Renamed Pasta")
    get calendar_feed_url(token: @token, format: :ics), headers: { "HTTP_IF_NONE_MATCH" => second_etag }
    assert_response :success, "renaming a recipe must invalidate the feed"
  end
end
