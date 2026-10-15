require "application_system_test_case"

# The shopping day control is a weekday list, and monthly swaps it for a day of
# the month. Request tests render the markup; this one runs the Stimulus
# toggle and the save, which is where a controller that never connects hides.
class HouseholdShoppingDayTest < ApplicationSystemTestCase
  setup do
    @household = households(:one)
    sign_in_as(family_members(:one))
  end

  test "a day you shop is a weekday, and monthly asks for a day of the month" do
    visit edit_admin_household_path

    assert_no_selector "input[type=date][name='household[shopping_anchor_on]']"
    weekday = find("select[name='household[shopping_wday]']")
    assert_equal "6", weekday.value
    assert_equal [ "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" ],
      weekday.all("option").map(&:text)
    assert_text "Every week, the list runs from this day"
    assert_no_text "we use its weekday"
    assert_selector "select[name='household[shopping_month_day]']", visible: :hidden

    select "Friday", from: "household_shopping_wday"
    click_on "Save Household Settings"

    assert_current_path admin_root_path
    assert_equal Date.new(2026, 1, 9), @household.reload.shopping_anchor_on

    visit edit_admin_household_path
    select "Every month", from: "How often"
    assert_selector "select[name='household[shopping_month_day]']", visible: :visible
    assert_selector "select[name='household[shopping_wday]']", visible: :hidden
    assert_text "day of the month"
    assert_equal "9", find("select[name='household[shopping_month_day]']").value

    select "31st", from: "household_shopping_month_day"
    click_on "Save Household Settings"
    assert_current_path admin_root_path

    @household.reload
    assert_equal "monthly", @household.shopping_frequency
    assert_equal 31, @household.shopping_anchor_on.day
    assert_equal Date.new(2026, 1, 31)..Date.new(2026, 2, 27), @household.shopping_schedule.period(Date.new(2026, 2, 10))
  end

  test "fortnightly keeps its week when the weekday changes" do
    @household.update!(shopping_frequency: "fortnightly", shopping_anchor_on: Date.new(2026, 10, 3))

    visit edit_admin_household_path
    select "Friday", from: "household_shopping_wday"
    click_on "Save Household Settings"
    assert_current_path admin_root_path

    assert_equal Date.new(2026, 10, 2), @household.reload.shopping_anchor_on
    assert_equal Date.new(2026, 10, 2)..Date.new(2026, 10, 15), @household.shopping_schedule.period(Date.new(2026, 10, 14))
  end
end
