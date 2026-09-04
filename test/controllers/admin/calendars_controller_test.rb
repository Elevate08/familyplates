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
    assert_includes response.body, "Calendar Subscriptions"
    assert_includes response.body, "Household Calendar Feed"
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
