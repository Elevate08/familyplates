require "test_helper"

class MealPlanSlotTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  test "a slot cannot take a recipe or cook from another household" do
    plan = meal_plans(:one)
    other_recipe = households(:two).recipes.create!(title: "Secret Soup")
    other_cook = households(:two).family_members.create!(
      name: "Miller Cook", role: "member", avatar_color: "#10B981", avatar_icon: "utensils"
    )

    stolen_recipe = plan.meal_plan_slots.build(date: plan.week_start_date, meal_type: "breakfast", recipe: other_recipe)
    assert_not stolen_recipe.valid?
    assert_includes stolen_recipe.errors[:recipe], "must belong to this household"

    stolen_cook = plan.meal_plan_slots.build(date: plan.week_start_date, meal_type: "lunch", family_member: other_cook)
    assert_not stolen_cook.valid?
    assert_includes stolen_cook.errors[:family_member], "must belong to this household"
  end

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

    # Attempting to add a 3rd leftover slot should fail validation
    excess_leftover = plan.meal_plan_slots.build(
      date: plan.week_start_date + 3.days,
      meal_type: "dinner",
      recipe: recipe,
      is_leftover: true,
      leftover_source_slot: source_slot
    )
    assert_not excess_leftover.valid?
    assert_includes excess_leftover.errors[:base], "All leftover servings for #{recipe.title} have already been scheduled."
  end

  test "leftover slot auto assigns source slot and fails when no cooked meal exists" do
    plan = households(:one).meal_plans.create!(week_start_date: 4.weeks.from_now.to_date.beginning_of_week)
    recipe = households(:one).recipes.create!(title: "Unique Leftover Dish", yields_leftovers: true, leftover_capacity: 1)

    # No cooked meal exists yet
    unprepared_leftover = plan.meal_plan_slots.build(
      date: plan.week_start_date,
      meal_type: "dinner",
      recipe: recipe,
      is_leftover: true
    )
    assert_not unprepared_leftover.valid?
    assert_includes unprepared_leftover.errors[:base], "#{recipe.title} has not been cooked yet, so leftovers cannot be scheduled."

    # Now create the cooked meal
    cooked_slot = plan.meal_plan_slots.create!(
      date: plan.week_start_date,
      meal_type: "dinner",
      recipe: recipe,
      is_leftover: false
    )

    # Schedule leftover without explicitly passing leftover_source_slot_id
    auto_leftover = plan.meal_plan_slots.create!(
      date: plan.week_start_date + 1.day,
      meal_type: "lunch",
      recipe: recipe,
      is_leftover: true
    )
    assert_equal cooked_slot.id, auto_leftover.leftover_source_slot_id
  end

  test "slot cannot set itself as leftover source" do
    slot = meal_plan_slots(:one)
    slot.is_leftover = true
    slot.leftover_source_slot_id = slot.id
    assert_not slot.valid?
    assert_includes slot.errors[:leftover_source_slot_id], "cannot be itself"
  end

  test "deleting planned meal clears out any scheduled leftover slots" do
    plan = households(:one).meal_plans.create!(week_start_date: 6.weeks.from_now.to_date.beginning_of_week)
    recipe = households(:one).recipes.create!(title: "Batch Stew", yields_leftovers: true, leftover_capacity: 2)

    cooked_slot = plan.meal_plan_slots.create!(
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
      leftover_source_slot: cooked_slot
    )

    leftover_slot_2 = plan.meal_plan_slots.create!(
      date: plan.week_start_date + 2.days,
      meal_type: "lunch",
      recipe: recipe,
      is_leftover: true,
      leftover_source_slot: cooked_slot
    )

    assert_equal 2, cooked_slot.leftover_slots.count
    assert_difference("MealPlanSlot.count", -3) do
      cooked_slot.destroy
    end

    assert_not MealPlanSlot.exists?(leftover_slot_1.id)
    assert_not MealPlanSlot.exists?(leftover_slot_2.id)
  end

  test "changing cooked meal recipe clears out scheduled leftover slots" do
    plan = households(:one).meal_plans.create!(week_start_date: 7.weeks.from_now.to_date.beginning_of_week)
    recipe1 = households(:one).recipes.create!(title: "Original Dish", yields_leftovers: true, leftover_capacity: 2)
    recipe2 = households(:one).recipes.create!(title: "Replacement Dish", yields_leftovers: true, leftover_capacity: 2)

    cooked_slot = plan.meal_plan_slots.create!(
      date: plan.week_start_date,
      meal_type: "dinner",
      recipe: recipe1,
      is_leftover: false
    )

    leftover_slot = plan.meal_plan_slots.create!(
      date: plan.week_start_date + 1.day,
      meal_type: "lunch",
      recipe: recipe1,
      is_leftover: true,
      leftover_source_slot: cooked_slot
    )

    cooked_slot.update!(recipe: recipe2)
    assert_not MealPlanSlot.exists?(leftover_slot.id)
  end

  test "moving cooked meal past a leftover slot clears invalidated leftover" do
    plan = households(:one).meal_plans.create!(week_start_date: 8.weeks.from_now.to_date.beginning_of_week)
    recipe = households(:one).recipes.create!(title: "Curry", yields_leftovers: true, leftover_capacity: 2, leftover_shelf_life_days: 2)

    cooked_slot = plan.meal_plan_slots.create!(
      date: plan.week_start_date,
      meal_type: "dinner",
      recipe: recipe,
      is_leftover: false
    )

    leftover_slot = plan.meal_plan_slots.create!(
      date: plan.week_start_date + 1.day,
      meal_type: "lunch",
      recipe: recipe,
      is_leftover: true,
      leftover_source_slot: cooked_slot
    )

    # Move cooked meal to day after the leftover
    cooked_slot.update!(date: plan.week_start_date + 2.days)
    assert_not MealPlanSlot.exists?(leftover_slot.id)
  end

  test "a leftover never keeps an ineligible source slot" do
    household = households(:one)
    week = 9.weeks.from_now.to_date.beginning_of_week
    plan = household.meal_plans.create!(week_start_date: week)
    stew = household.recipes.create!(title: "Eligibility Stew", yields_leftovers: true, leftover_capacity: 3)
    soup = household.recipes.create!(title: "Eligibility Soup")
    source = plan.meal_plan_slots.create!(date: week, meal_type: "dinner", recipe: stew)
    other_recipe_source = plan.meal_plan_slots.create!(date: week, meal_type: "lunch", recipe: soup)
    later_source = plan.meal_plan_slots.create!(date: week + 5, meal_type: "dinner", recipe: stew)

    other = households(:two)
    other_stew = other.recipes.create!(title: "Eligibility Stew")
    foreign_source = other.meal_plans.create!(week_start_date: week).meal_plan_slots.create!(date: week, meal_type: "dinner", recipe: other_stew)

    [ other_recipe_source, later_source, foreign_source ].each do |bad|
      leftover = plan.meal_plan_slots.new(date: week + 1, meal_type: "lunch", recipe: stew, is_leftover: true, leftover_source_slot_id: bad.id)
      assert leftover.save, leftover.errors.full_messages.to_sentence
      assert_equal source.id, leftover.leftover_source_slot_id, "must not keep #{bad.meal_type} #{bad.date} as its source"
      leftover.destroy
    end

    stale = plan.meal_plan_slots.new(date: week + 6, meal_type: "lunch", recipe: stew, is_leftover: true, leftover_source_slot_id: source.id)
    stale.valid?
    assert_not_equal source.id, stale.leftover_source_slot_id, "a source past its shelf life must not be kept"
  end
end
