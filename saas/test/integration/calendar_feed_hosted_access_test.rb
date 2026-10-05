# frozen_string_literal: true

require "test_helper"

class CalendarFeedHostedAccessTest < ActionDispatch::IntegrationTest
  setup do
    FamilyPlates.config.reset!
    FamilyPlates.config.mode = "hosted"
    @household = households(:one)
    @token = @household.calendar_feed_token
  end

  teardown do
    FamilyPlates.config.reset!
  end

  test "an entitled hosted household still serves its feed" do
    @household.update_columns(created_at: Time.current)
    assert @household.reload.entitled?

    get calendar_feed_url(token: @token, format: :ics)

    assert_response :success
    assert_includes response.body, "BEGIN:VCALENDAR"
  end

  test "a suspended household's feed is a 404 with no calendar body" do
    @household.update_columns(suspended_at: Time.current)

    get calendar_feed_url(token: @token, format: :ics)

    assert_response :not_found
    assert_not_includes response.body, "VCALENDAR"
  end

  test "a suspended household's member feed is a 404" do
    @household.update_columns(suspended_at: Time.current)

    get calendar_member_feed_url(token: @token, member_id: family_members(:one).id, format: :ics)

    assert_response :not_found
    assert_not_includes response.body, "VCALENDAR"
  end

  # 403, not 404: the household still exists and the same link works again
  # once it subscribes, so calendar apps should keep the subscription.
  test "an unentitled hosted household's feed is a 403 with no calendar body" do
    @household.update_columns(created_at: 25.days.ago)
    assert_not @household.reload.entitled?

    get calendar_feed_url(token: @token, format: :ics)

    assert_response :forbidden
    assert_not_includes response.body, "VCALENDAR"
  end
end
