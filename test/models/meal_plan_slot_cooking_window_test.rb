require "test_helper"

# "Which meal is being cooked right now" is decided from the household's own
# serving times, so these tests pin the window arithmetic rather than a guess at
# what o'clock breakfast is.
class MealPlanSlotCookingWindowTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
    @household.update!(breakfast_time: "08:00", lunch_time: "12:30", dinner_time: "18:00")
    @plan = @household.current_meal_plan(Date.current.beginning_of_week)
    @recipe = @household.recipes.create!(title: "Window Subject", instructions: "1. Cook.")
  end

  def slot_for(meal_type, date: Date.current, scheduled_time: nil, recipe: @recipe)
    @plan.meal_plan_slots.create!(
      date: date, meal_type: meal_type, recipe: recipe, scheduled_time: scheduled_time
    )
  end

  def at(hour, minute = 0, on: Date.current)
    Time.zone.local(on.year, on.month, on.day, hour, minute, 0)
  end

  test "serving time comes from the household when the slot names none" do
    assert_equal at(18), slot_for("dinner").scheduled_at
    assert_equal at(8), slot_for("breakfast").scheduled_at
  end

  test "a time on the slot itself wins over the household's" do
    assert_equal at(19, 30), slot_for("dinner", scheduled_time: "19:30").scheduled_at
  end

  test "the cooking window opens two hours before the meal and closes ninety minutes after" do
    dinner = slot_for("dinner")

    assert_not dinner.cooking_now?(at(15, 59))
    assert dinner.cooking_now?(at(16, 0)), "two hours ahead: the roast goes in"
    assert dinner.cooking_now?(at(18, 0))
    assert dinner.cooking_now?(at(19, 30)), "ninety minutes past: dinner ran late"
    assert_not dinner.cooking_now?(at(19, 31))
  end

  test "picks the meal whose window is open" do
    slot_for("breakfast")
    lunch = slot_for("lunch")
    slot_for("dinner")

    assert_equal lunch, MealPlanSlot.cooking_now(@household, at: at(12, 0))
  end

  test "when two windows overlap it picks the meal due soonest" do
    lunch = slot_for("lunch")                          # 12:30, window 10:30-14:00
    dinner = slot_for("dinner", scheduled_time: "15:00") # window 13:00-16:30

    assert_equal lunch, MealPlanSlot.cooking_now(@household, at: at(13, 15))
    assert_equal dinner, MealPlanSlot.cooking_now(@household, at: at(14, 30))
  end

  test "no window open means no meal is being cooked" do
    slot_for("dinner")

    assert_nil MealPlanSlot.cooking_now(@household, at: at(10, 0))
  end

  test "a slot with no recipe is never the meal being cooked" do
    slot_for("dinner", recipe: nil)

    assert_nil MealPlanSlot.cooking_now(@household, at: at(17, 0))
  end

  test "another household's meal is never picked" do
    other = households(:two)
    other_plan = other.current_meal_plan(Date.current.beginning_of_week)
    other_plan.meal_plan_slots.create!(
      date: Date.current, meal_type: "dinner",
      recipe: other.recipes.create!(title: "Theirs", instructions: "1. Cook.")
    )

    assert_nil MealPlanSlot.cooking_now(@household, at: at(17, 0))
  end

  test "the fallback prefers a meal still ahead over one already served" do
    breakfast = slot_for("breakfast")
    dinner = slot_for("dinner")

    assert_equal dinner, MealPlanSlot.next_planned(@household, at: at(15, 0))
    assert_equal breakfast, MealPlanSlot.next_planned(@household, at: at(5, 0))
  end

  test "the fallback settles for an already-served meal when nothing is left today" do
    breakfast = slot_for("breakfast")

    assert_equal breakfast, MealPlanSlot.next_planned(@household, at: at(22, 0))
  end

  test "the fallback stays inside today" do
    slot_for("dinner", date: Date.current + 1)

    assert_nil MealPlanSlot.next_planned(@household, at: at(12, 0))
  end

  # --- Read against the household's clock, not the server's -----------------

  test "a meal time means that hour in the kitchen, not that hour in UTC" do
    @household.update!(time_zone: "America/Chicago")
    dinner = slot_for("dinner", date: Date.new(2026, 9, 5))

    # 18:00 CDT is 23:00 UTC.
    assert_equal Time.utc(2026, 9, 5, 23, 0, 0), dinner.scheduled_at.utc
  end

  test "the cooking window follows the household's clock" do
    @household.update!(time_zone: "America/Chicago")
    slot_for("dinner", date: Date.new(2026, 9, 5))

    # 17:30 local is 22:30 UTC - inside the window. On a UTC-only reading the
    # same instant would be hours past dinner and would match nothing.
    assert_not_nil MealPlanSlot.cooking_now(@household, at: Time.utc(2026, 9, 5, 22, 30, 0))
    assert_nil MealPlanSlot.cooking_now(@household, at: Time.utc(2026, 9, 5, 18, 0, 0))
  end

  test "the fallback's idea of today is the kitchen's day" do
    @household.update!(time_zone: "America/Chicago")
    tonight = slot_for("dinner", date: Date.new(2026, 9, 5))
    slot_for("breakfast", date: Date.new(2026, 9, 6))

    # 01:00 UTC on the 6th is still the evening of the 5th in Chicago, so the
    # meal on offer is that evening's dinner, not the next morning's breakfast.
    assert_equal tonight, MealPlanSlot.next_planned(@household, at: Time.utc(2026, 9, 6, 1, 0, 0))
  end

  test "upcoming meals are listed in serving order and start from now" do
    slot_for("breakfast")
    lunch = slot_for("lunch")
    dinner = slot_for("dinner")
    tomorrow = slot_for("breakfast", date: Date.current + 1)

    assert_equal [ lunch, dinner, tomorrow ], MealPlanSlot.upcoming_planned(@household, at: at(11, 0))
  end
end
