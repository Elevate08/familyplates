require "test_helper"

class MealPlanSlotTest < ActiveSupport::TestCase
  test "validates meal_type inclusion" do
    slot = MealPlanSlot.new(meal_plan: meal_plans(:one), date: Date.current, meal_type: "midnight_snack")
    assert_not slot.valid?
    assert_includes slot.errors[:meal_type], "is not included in the list"
  end

  test "display_title falls back to custom_title or default" do
    slot = meal_plan_slots(:one)
    assert_equal recipes(:one).title, slot.display_title

    custom_slot = MealPlanSlot.new(custom_title: "Dining Out")
    assert_equal "Dining Out", custom_slot.display_title
  end
end
