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

  test "should update meal times" do
    sign_in_as(@admin)

    patch admin_household_url, params: {
      household: {
        breakfast_time: "07:45",
        lunch_time: "12:15",
        dinner_time: "18:30"
      }
    }

    assert_redirected_to admin_root_url
    @household.reload
    assert_equal "07:45", @household.breakfast_time
    assert_equal "12:15", @household.lunch_time
    assert_equal "18:30", @household.dinner_time
  end

  test "should reset join code for admin" do
    sign_in_as(@admin)
    old_code = @household.join_code

    post reset_join_code_admin_household_url

    assert_redirected_to edit_admin_household_url
    assert_not_equal old_code, @household.reload.join_code
    assert_match(/\A[A-Z0-9]{4}(?:-[A-Z0-9]{4}){2}\z/, @household.join_code)
  end

  # @card-62.7
  test "an organizer chooses how often and which weekday the household shops" do
    sign_in_as(@admin)

    get edit_admin_household_url
    assert_select "select[name='household[shopping_frequency]'] option", count: 3
    assert_select "input[type=date][name='household[shopping_anchor_on]']", count: 0
    assert_select "select[name='household[shopping_wday]'] option", count: 7
    assert_equal %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday],
      css_select("select[name='household[shopping_wday]'] option").map(&:text)
    assert_select "select[name='household[shopping_wday]'] option[selected]", text: "Saturday"
    assert_select "select[name='household[shopping_wday]']:not([disabled])"
    assert_select "[data-shopping-day-target=monthday][hidden] select[name='household[shopping_month_day]'][disabled]"
    assert_select "span", text: /Every week, the list runs from this day/
    assert_select "span", text: /we use its weekday/, count: 0

    patch admin_household_url, params: { household: { shopping_frequency: "weekly", shopping_wday: "5" } }

    assert_redirected_to admin_root_url
    @household.reload
    assert_equal "weekly", @household.shopping_frequency
    assert_equal Date.new(2026, 1, 9), @household.shopping_anchor_on
    assert_equal 5, @household.shopping_anchor_on.wday
  end

  # @card-62.7
  test "monthly shopping asks for a day of the month and keeps one already stored" do
    sign_in_as(@admin)
    @household.update!(shopping_frequency: "monthly", shopping_anchor_on: Date.new(2026, 2, 28))

    get edit_admin_household_url
    assert_select "[data-shopping-day-target=weekday][hidden] select[name='household[shopping_wday]'][disabled]"
    assert_select "select[name='household[shopping_month_day]']:not([disabled]) option[selected]", text: "28th"
    assert_select "span", text: /day of the month/

    patch admin_household_url, params: { household: { shopping_frequency: "monthly", shopping_month_day: "28" } }
    assert_redirected_to admin_root_url
    assert_equal Date.new(2026, 2, 28), @household.reload.shopping_anchor_on

    patch admin_household_url, params: { household: { shopping_frequency: "monthly", shopping_month_day: "31" } }
    assert_equal 31, @household.reload.shopping_anchor_on.day
    assert_equal "monthly", @household.shopping_frequency
  end

  # @card-62.7
  test "fortnightly slides onto the chosen weekday without flipping weeks" do
    sign_in_as(@admin)
    @household.update!(shopping_frequency: "fortnightly", shopping_anchor_on: Date.new(2026, 10, 3))

    patch admin_household_url, params: { household: { shopping_frequency: "fortnightly", shopping_wday: "5" } }

    assert_redirected_to admin_root_url
    assert_equal Date.new(2026, 10, 2), @household.reload.shopping_anchor_on
  end

  # @card-62.7
  test "an unknown shopping frequency or a missing day is rejected" do
    sign_in_as(@admin)

    patch admin_household_url, params: { household: { shopping_frequency: "daily" } }
    assert_response :unprocessable_entity
    assert_equal "weekly", @household.reload.shopping_frequency

    patch admin_household_url, params: { household: { shopping_wday: "" } }
    assert_response :unprocessable_entity
    assert_equal Date.new(2026, 1, 3), @household.reload.shopping_anchor_on
    assert_match "A day you shop must be a day of the week", response.body

    patch admin_household_url, params: { household: { shopping_frequency: "monthly", shopping_month_day: "32" } }
    assert_response :unprocessable_entity
    assert_equal "weekly", @household.reload.shopping_frequency
    assert_equal Date.new(2026, 1, 3), @household.shopping_anchor_on

    patch admin_household_url, params: { household: { shopping_anchor_on: "2026-06-15", shopping_wday: "6" } }
    assert_redirected_to admin_root_url
    assert_equal Date.new(2026, 1, 3), @household.reload.shopping_anchor_on
  end

  # @card-62.7
  test "a member cannot change the shopping schedule" do
    sign_in_as(@member)

    patch admin_household_url, params: { household: { shopping_frequency: "monthly" } }

    assert_redirected_to root_url
    assert_equal "weekly", @household.reload.shopping_frequency
  end

  # @card-62.9
  test "households shop weekly on Saturday until changed" do
    assert_equal "weekly", @household.shopping_frequency
    assert_equal 6, @household.shopping_anchor_on.wday
  end
end
