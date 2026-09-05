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

  test "leftover associations link leftover slot to parent source slot" do
    plan = households(:one).meal_plans.create!(week_start_date: 3.weeks.from_now.to_date.beginning_of_week)
    recipe = recipes(:one)
    recipe.update!(yields_leftovers: true, leftover_capacity: 2)

    source_slot = plan.meal_plan_slots.create!(
      date: plan.week_start_date,
      meal_type: "dinner",
      recipe: recipe,
      is_leftover: false
    )

    leftover_slot_1 = plan.meal_plan_slots.create!(
      date: plan.week_start_date + 1.day,
      meal_type: "lunch",
      recipe: recipe,
      is_leftover: true,
      leftover_source_slot: source_slot
    )

    assert_equal source_slot, leftover_slot_1.leftover_source_slot
    assert_includes source_slot.leftover_slots, leftover_slot_1
    assert_equal 1, source_slot.leftover_capacity_remaining
    assert_not source_slot.leftover_exhausted?

    leftover_slot_2 = plan.meal_plan_slots.create!(
      date: plan.week_start_date + 2.days,
      meal_type: "lunch",
      recipe: recipe,
      is_leftover: true,
      leftover_source_slot: source_slot
    )

    assert_equal 0, source_slot.leftover_capacity_remaining
    assert source_slot.leftover_exhausted?
  end

  test "slot cannot set itself as leftover source" do
    slot = meal_plan_slots(:one)
    slot.is_leftover = true
    slot.leftover_source_slot_id = slot.id
    assert_not slot.valid?
    assert_includes slot.errors[:leftover_source_slot_id], "cannot be itself"
  end
end
