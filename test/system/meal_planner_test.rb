require "application_system_test_case"

# The slot modal is the most JavaScript-heavy screen in the app: a custom recipe
# picker, leftover candidates, and a reschedule panel. Every slot on the page
# rendered the same id for each of its fields until the markup audit caught it,
# so getElementById could reach into a different day's modal entirely.
class MealPlannerTest < ApplicationSystemTestCase
  setup do
    @admin = family_members(:one)
    @household = households(:one)
    @plan = @household.current_meal_plan
    @recipe = @household.recipes.create!(title: "Planner Subject", instructions: "Cook.", total_time: 30)

    sign_in_as(@admin)
    visit meal_plan_path(@plan)
  end

  test "every slot's fields carry ids of their own" do
    ids = all("input[id$='_custom_title']", visible: :all).map { |e| e[:id] }

    assert_operator ids.length, :>, 1, "precondition: several slots rendered"
    assert_equal ids.uniq.length, ids.length,
      "duplicate ids mean getElementById reaches into the wrong slot's modal"
  end

  test "each slot's labels point at that slot's own fields" do
    labels = all("label[for$='_custom_title']", visible: :all).map { |e| e[:for] }
    ids = all("input[id$='_custom_title']", visible: :all).map { |e| e[:id] }

    assert_operator labels.length, :>, 1
    labels.each { |target| assert_includes ids, target, "label points at a field that is not on the page" }
  end

  test "opening a slot shows its modal" do
    # The trigger is the slot card itself, a div, not a button.
    first("[data-action*='slot-modal#open']").click

    assert_selector "input[id$='_custom_title']", visible: true, wait: 5
  end

  test "the month view renders without browser errors" do
    visit meal_plan_path(@plan, view: "month")

    assert_selector "body"
    assert_no_browser_errors
  end

  test "the print view renders without browser errors" do
    visit print_meal_plan_path(@plan)

    assert_selector "body"
    assert_no_browser_errors
  end

  test "leftover capacity depletion hides depleted meal from subsequent slots" do
    monday = @plan.week_start_date
    tuesday = monday + 1.day
    wednesday = monday + 2.days

    stew = @household.recipes.create!(
      title: "Hearty Beef Stew",
      yields_leftovers: true,
      leftover_capacity: 1,
      leftover_shelf_life_days: 4,
      instructions: "Simmer."
    )

    # Monday dinner: fresh cooked batch
    @plan.meal_plan_slots.where(date: monday, meal_type: "dinner").destroy_all
    @plan.meal_plan_slots.create!(
      date: monday,
      meal_type: "dinner",
      recipe: stew,
      is_leftover: false
    )

    visit meal_plan_path(@plan)

    # Open Tuesday lunch slot
    tue_slot_frame = "slot_#{tuesday}_lunch"
    within("##{tue_slot_frame}") do
      first("[data-action*='slot-modal#open']").click
      assert_text "Hearty Beef Stew"
      assert_text "Last one!"

      # Click the leftover candidate button
      find("button[data-action*='slot-modal#selectLeftover']", text: "Hearty Beef Stew").click
      click_on "Schedule Meal"
    end

    # Tuesday lunch now has the planned leftover
    assert_selector "##{tue_slot_frame}", text: "Hearty Beef Stew"

    # Now open Wednesday lunch slot
    wed_slot_frame = "slot_#{wednesday}_lunch"
    find("##{wed_slot_frame} [data-action*='slot-modal#open']").click
    within("##{wed_slot_frame}") do
      # Since capacity was 1 and it was used on Tuesday, it should not appear in leftover quick pick
      assert_no_selector "button[data-action*='slot-modal#selectLeftover']", text: "Hearty Beef Stew"
    end
  end

  test "leftover shelf life expiration hides meal past freshness date" do
    monday = @plan.week_start_date
    tuesday = monday + 1.day
    wednesday = monday + 2.days

    ceviche = @household.recipes.create!(
      title: "Citrus Ceviche",
      yields_leftovers: true,
      leftover_capacity: 3,
      leftover_shelf_life_days: 1, # Only fresh for 1 day
      instructions: "Marinate fresh fish."
    )

    # Monday dinner: fresh cooked batch
    @plan.meal_plan_slots.where(date: monday, meal_type: "dinner").destroy_all
    @plan.meal_plan_slots.create!(
      date: monday,
      meal_type: "dinner",
      recipe: ceviche,
      is_leftover: false
    )

    visit meal_plan_path(@plan)

    # Tuesday lunch (1 day later): should be available
    tue_slot_frame = "slot_#{tuesday}_lunch"
    within("##{tue_slot_frame}") do
      first("[data-action*='slot-modal#open']").click
      assert_selector "button[data-action*='slot-modal#selectLeftover']", text: "Citrus Ceviche"
      # Close modal
      first("button[data-action*='slot-modal#close']").click
    end

    # Wednesday lunch (2 days later): has expired, should not be available
    wed_slot_frame = "slot_#{wednesday}_lunch"
    within("##{wed_slot_frame}") do
      first("[data-action*='slot-modal#open']").click
      assert_no_selector "button[data-action*='slot-modal#selectLeftover']", text: "Citrus Ceviche"
    end
  end
end
