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

  test "enqueues sync job with upsert when meal is created or updated" do
    household = households(:one)
    household.update!(google_calendar_enabled: true, google_calendar_id: "family@group.calendar.google.com")
    plan = meal_plans(:one)

    assert_enqueued_with(job: SyncMealPlanSlotJob, args: ->(args) { args[1] == "upsert" }) do
      plan.meal_plan_slots.create!(
        date: plan.week_start_date + 3.days,
        meal_type: "dinner",
        custom_title: "Homemade Lasagna"
      )
    end
  end

  test "enqueues sync job with delete when slot is destroyed" do
    household = households(:one)
    household.update!(google_calendar_enabled: true, google_calendar_id: "family@group.calendar.google.com")
    slot = meal_plan_slots(:one)
    slot.update_column(:google_event_id, "gcal_event_to_delete")

    assert_enqueued_with(job: SyncMealPlanSlotJob, args: [ nil, "delete", "gcal_event_to_delete", household.id ]) do
      slot.destroy
    end
  end

  test "enqueues sync job with delete when slot meal is cleared" do
    household = households(:one)
    household.update!(google_calendar_enabled: true, google_calendar_id: "family@group.calendar.google.com")
    slot = meal_plan_slots(:one)
    slot.update_column(:google_event_id, "gcal_event_cleared")

    assert_enqueued_with(job: SyncMealPlanSlotJob, args: [ slot.id, "delete", "gcal_event_cleared", household.id ]) do
      slot.update!(recipe: nil, custom_title: nil)
    end
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
