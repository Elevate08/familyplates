require "test_helper"

class MealPlanTest < ActiveSupport::TestCase
  test "validates uniqueness of week_start_date per household" do
    duplicate = MealPlan.new(household: households(:one), week_start_date: meal_plans(:one).week_start_date)
    assert_not duplicate.valid?
  end

  test "returns 7 days" do
    plan = meal_plans(:one)
    assert_equal 7, plan.days.count
    assert_equal plan.week_start_date, plan.days.first
    assert_equal plan.week_start_date + 6.days, plan.days.last
  end

  test "slot_for returns correct slot" do
    plan = meal_plans(:one)
    slot = plan.slot_for(Date.current.beginning_of_week, "dinner")
    assert_not_nil slot
    assert_equal recipes(:one), slot.recipe
  end
end
