require "application_system_test_case"

# The grocery checklist across devices. A second Capybara session is a second
# browser with its own cookies and localStorage, standing in for a second phone.
class SharedGroceryTicksTest < ApplicationSystemTestCase
  setup do
    page.driver.browser.manage.window.resize_to(1400, 1000)

    @household = households(:one)
    @monday = @household.today.beginning_of_week
    MealPlanSlot.where(meal_plan: @household.meal_plans).destroy_all

    recipe = @household.recipes.create!(title: "Lentil Soup", instructions: "1. Simmer.")
    recipe.recipe_ingredients.create!(name: "Red lentils", quantity: 1, unit: "cup", aisle_category: "Pantry & Grains")
    @household.current_meal_plan.meal_plan_slots.create!(date: @monday, meal_type: "dinner", recipe: recipe)

    sign_in_as(family_members(:one))
  end

  # @card-62.10
  test "a tick made on one device shows on another, and Reset clears it for both" do
    visit grocery_list_path(from: @monday.iso8601, to: (@monday + 6.days).iso8601)
    tick_lentils
    assert_selector "input[type=checkbox]:checked"
    wait_for_tick_count(1)

    Capybara.using_session(:other_phone) do
      sign_in_as(family_members(:two))
      visit grocery_list_path(from: @monday.iso8601, to: (@monday + 6.days).iso8601)
      assert_selector "input[type=checkbox]:checked"
      # Read-only: ordinary members see the ticks but cannot change them.
      assert_selector "input[type=checkbox][disabled]"
    end

    # @card-62.12
    find("button", text: "Reset").click
    click_on "Reset Checklist"
    assert_no_selector "input[type=checkbox]:checked"
    wait_for_tick_count(0)

    Capybara.using_session(:other_phone) do
      visit grocery_list_path(from: @monday.iso8601, to: (@monday + 6.days).iso8601)
      assert_no_selector "input[type=checkbox]:checked"
    end
  end

  # @card-62.10
  test "a tick shows on a page that is already open when the tab is shown again" do
    path = grocery_list_path(from: @monday.iso8601, to: (@monday + 6.days).iso8601)
    visit path

    GroceryTick.record!(household: @household, from: @monday, to: @monday + 6.days,
                        item_key: lentils_key, checked: true, changed_at: Time.current, family_member: nil)

    page.execute_script("document.dispatchEvent(new Event('visibilitychange')); window.dispatchEvent(new Event('focus'))")
    assert_selector "input[type=checkbox]:checked"
  end

  # @card-62.11
  test "a tick made offline is saved once the device is back online" do
    visit grocery_list_path(from: @monday.iso8601, to: (@monday + 6.days).iso8601)

    go_offline(true)
    tick_lentils
    assert_selector "input[type=checkbox]:checked"
    assert_equal 0, @household.grocery_ticks.count

    go_offline(false)
    page.execute_script("window.dispatchEvent(new Event('online'))")
    wait_for_tick_count(1)
    assert_equal true, @household.grocery_ticks.first.checked
  end

  private

  def lentils_key = "pantry-grains_red-lentils_cup"

  def tick_lentils
    find("[data-checklist-target='item']", text: "Red lentils").find("input[type=checkbox]").click
  end

  def go_offline(offline)
    page.driver.browser.network_conditions = { offline: offline, latency: 0, throughput: -1 }
  end

  # The save is fire-and-forget, so there is nothing on the page to wait on.
  def wait_for_tick_count(expected)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until @household.grocery_ticks.count == expected || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.1
    end
    assert_equal expected, @household.grocery_ticks.count
  end
end
