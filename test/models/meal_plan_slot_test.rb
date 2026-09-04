require "test_helper"

class MealPlanSlotTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
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

  test "is_leftover defaults to false and can be flagged" do
    slot = MealPlanSlot.new(meal_plan: meal_plans(:one), date: Date.current, meal_type: "lunch")
    assert_equal false, slot.is_leftover?

    slot.is_leftover = true
    assert slot.is_leftover?
  end

  test "ingredient aggregator excludes leftover slots to prevent double-counting ingredients" do
    plan = meal_plans(:one)
    recipe = recipes(:one)
    MealPlanSlot.delete_all

    # 1. First fresh dinner
    plan.meal_plan_slots.create!(
      date: plan.week_start_date,
      meal_type: "dinner",
      recipe: recipe,
      is_leftover: false
    )

    # 2. Next day lunch marked as leftover of the same recipe
    plan.meal_plan_slots.create!(
      date: plan.week_start_date + 1.day,
      meal_type: "lunch",
      recipe: recipe,
      is_leftover: true
    )

    agg = IngredientAggregator.call(plan)
    # The ingredients should only be counted once from the fresh slot
    sample_ingredient = recipe.recipe_ingredients.first
    if sample_ingredient
      norm_name = sample_ingredient.name.capitalize
      found_item = agg[:aisles].values.flatten.find { |i| i[:name].downcase == norm_name.downcase }
      if found_item
        assert_equal (sample_ingredient.quantity || 1.0), found_item[:quantity]
      end
    end
  end
end
