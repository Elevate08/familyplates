require "application_system_test_case"

# The planner-to-grocery hop and the range bar, in a real browser.
class GroceryRangeTest < ApplicationSystemTestCase
  setup do
    page.driver.browser.manage.window.resize_to(1400, 1000)

    @household = households(:one)
    @monday = @household.today.beginning_of_week
    MealPlanSlot.where(meal_plan: @household.meal_plans).destroy_all

    plan_dinner(@monday, "Lentil Soup", "Red lentils")
    plan_dinner(@monday + 7.days, "Squash Curry", "Butternut")

    sign_in_as(family_members(:one))
  end

  # @card-62.4
  # @card-62.2
  test "the planner week links to its list, and Next week shows the following week's items" do
    visit meal_plans_path(week: @monday)
    click_on "Grocery list"

    assert_selector "span.item-label", text: "Red lentils"
    assert_no_selector "span.item-label", text: "Butternut"

    click_on "Next week"

    assert_selector "span.item-label", text: "Butternut"
    assert_no_selector "span.item-label", text: "Red lentils"
  end

  # @card-62.2
  test "a custom date range shows every meal in it" do
    visit grocery_list_path

    find("summary", text: "Custom dates").click
    fill_in "from", with: @monday
    fill_in "to", with: @monday + 13.days
    click_on "Show list"

    assert_selector "span.item-label", text: "Red lentils"
    assert_selector "span.item-label", text: "Butternut"
  end

  private

  def plan_dinner(date, title, ingredient)
    recipe = @household.recipes.create!(title: title, instructions: "Cook.")
    recipe.recipe_ingredients.create!(name: ingredient, quantity: 1, unit: "cup", aisle_category: "Produce")
    @household.current_meal_plan(date.beginning_of_week).meal_plan_slots.create!(date: date, meal_type: "dinner", recipe: recipe)
  end
end
