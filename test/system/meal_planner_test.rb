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
end
