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

    assert_enqueued_with(job: SyncMealPlanSlotJob, args: [nil, "delete", "gcal_event_to_delete", household.id]) do
      slot.destroy
    end
  end

  test "enqueues sync job with delete when slot meal is cleared" do
    household = households(:one)
    household.update!(google_calendar_enabled: true, google_calendar_id: "family@group.calendar.google.com")
    slot = meal_plan_slots(:one)
    slot.update_column(:google_event_id, "gcal_event_cleared")

    assert_enqueued_with(job: SyncMealPlanSlotJob, args: [slot.id, "delete", "gcal_event_cleared", household.id]) do
      slot.update!(recipe: nil, custom_title: nil)
    end
  end
end
