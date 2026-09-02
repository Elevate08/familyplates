require "test_helper"

class Admin::HouseholdsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @admin = family_members(:one) # admin
    @member = family_members(:two) # member
  end

  test "should block non-admin" do
    sign_in_as(@member)

    get edit_admin_household_url
    assert_redirected_to root_url
  end

  test "should get edit for admin" do
    sign_in_as(@admin)

    get edit_admin_household_url
    assert_response :success
  end

  test "should update household name" do
    sign_in_as(@admin)

    patch admin_household_url, params: {
      household: {
        name: "The Spencer Gourmet Kitchen"
      }
    }

    assert_redirected_to admin_root_url
    assert_equal "The Spencer Gourmet Kitchen", @household.reload.name
  end

  test "should update google calendar settings and meal times" do
    sign_in_as(@admin)

    patch admin_household_url, params: {
      household: {
        google_calendar_id: "family-meals@group.calendar.google.com",
        google_calendar_enabled: "1",
        breakfast_time: "07:45",
        lunch_time: "12:15",
        dinner_time: "18:30"
      }
    }

    assert_redirected_to admin_root_url
    @household.reload
    assert_equal "family-meals@group.calendar.google.com", @household.google_calendar_id
    assert_equal true, @household.google_calendar_enabled
    assert_equal "07:45", @household.breakfast_time
    assert_equal "12:15", @household.lunch_time
    assert_equal "18:30", @household.dinner_time
  end
end
