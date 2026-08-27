require "test_helper"

class HouseholdTest < ActiveSupport::TestCase
  test "initializes with default meal schedule times" do
    household = Household.create!(name: "Test Family")
    assert_equal "08:00", household.breakfast_time
    assert_equal "12:30", household.lunch_time
    assert_equal "18:00", household.dinner_time
    assert_equal false, household.google_calendar_enabled
  end

  test "validates name presence" do
    household = Household.new(name: "")
    assert_not household.valid?
    assert_includes household.errors[:name], "can't be blank"
  end
end
