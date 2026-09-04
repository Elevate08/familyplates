require "test_helper"

class Admin::CalendarsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @admin = family_members(:one)
    @member = family_members(:two)
  end

  test "should block non-admin" do
    sign_in_as(@member)
    get edit_admin_calendar_url
    assert_redirected_to root_url
  end

  test "should get edit for admin" do
    sign_in_as(@admin)
    get edit_admin_calendar_url
    assert_response :success
  end

  test "should update calendar settings" do
    sign_in_as(@admin)
    patch admin_calendar_url, params: {
      household: {
        google_calendar_id: "family-meals@group.calendar.google.com",
        google_calendar_enabled: "1"
      }
    }
    assert_redirected_to edit_admin_calendar_url
    @household.reload
    assert_equal "family-meals@group.calendar.google.com", @household.google_calendar_id
    assert_equal true, @household.google_calendar_enabled
  end

  test "should test connection" do
    sign_in_as(@admin)
    post test_connection_admin_calendar_url, params: {
      google_calendar_id: "family-meals@group.calendar.google.com"
    }
    assert_redirected_to edit_admin_calendar_url
  end

  test "should sync plan" do
    sign_in_as(@admin)
    post sync_plan_admin_calendar_url
    assert_redirected_to edit_admin_calendar_url
    assert_equal "Full meal plan sync to Google Calendar completed! 📅", flash[:notice]

    post sync_plan_admin_calendar_url, as: :json
    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["success"]
  end

  test "should regenerate calendar feed token for admin" do
    sign_in_as(@admin)
    original_token = @household.calendar_feed_token

    post regenerate_feed_token_admin_calendar_url
    assert_redirected_to edit_admin_calendar_url
    assert_equal "Calendar subscription feed link has been regenerated! 🔄 Previous subscription links have been revoked.", flash[:notice]

    @household.reload
    assert_not_equal original_token, @household.calendar_feed_token
    assert @household.calendar_feed_token.present?
  end

  test "should block non-admin from regenerating calendar feed token" do
    sign_in_as(@member)
    post regenerate_feed_token_admin_calendar_url
    assert_redirected_to root_url
  end
end
