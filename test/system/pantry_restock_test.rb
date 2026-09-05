require "application_system_test_case"

# The two halves that only exist in a browser: the Turbo Stream that swaps the
# toggle in place, and the grocery checkbox that reaches back to the pantry.
# A request test can drive both endpoints directly and prove neither is wired up.
class PantryRestockTest < ApplicationSystemTestCase
  setup do
    page.driver.browser.manage.window.resize_to(1400, 1000)

    @household = households(:one)
    @plan = @household.current_meal_plan
    @plan.meal_plan_slots.destroy_all

    @recipe = @household.recipes.create!(title: "Buttered Toast", instructions: "1. Toast it.")
    @recipe.recipe_ingredients.create!(name: "Butter", quantity: 2, unit: "tbsp", aisle_category: "Dairy & Refrigerated")
    @plan.meal_plan_slots.create!(date: @household.today, meal_type: "breakfast", recipe: @recipe)

    @butter = @household.pantry_items.create!(name: "Butter", aisle_category: "Dairy & Refrigerated", is_staple: true)

    sign_in_as(family_members(:one))
  end

  test "flagging a staple low from the pantry swaps the control in place" do
    visit pantry_items_path

    within "##{dom_id(@butter)}" do
      assert_no_text(/low/i)
      find("button[title*='running low']").click
      assert_text(/low/i)
    end

    assert_predicate @butter.reload, :low_stock?

    # And back again, without a page reload in either direction.
    within "##{dom_id(@butter)}" do
      find("button[title*='restocked']").click
      assert_no_text(/low/i)
    end

    assert_not_predicate @butter.reload, :low_stock?
  end

  test "a cook can flag a staple low from the recipe they are reading" do
    visit recipe_path(@recipe)

    find("##{dom_id(@butter, :stock)} button").click

    assert_selector "##{dom_id(@butter, :stock)}", text: /low/i
    assert_predicate @butter.reload, :low_stock?
  end

  test "ticking a restock line on the grocery list marks the staple bought" do
    @butter.mark_low!
    visit grocery_list_path

    # The badge is uppercased in CSS, not in the DOM.
    assert_text(/restock/i)
    row = find("[data-pantry-item-id='#{@butter.id}']")

    row.find("input[type='checkbox']").click
    assert_low_stock false, "checking it off should have restocked the pantry item"

    # Un-ticking is the "wrong row" case, and has to put the flag back.
    row.find("input[type='checkbox']").click
    assert_low_stock true, "un-checking it should have flagged it low again"
  end

  test "an ordinary grocery line touches no pantry item" do
    visit grocery_list_path

    assert_no_selector "[data-restock-url]"
  end

  private

  def dom_id(record, prefix = nil)
    ActionView::RecordIdentifier.dom_id(record, prefix)
  end

  # The post is fire-and-forget - nothing on the page changes - so there is no
  # DOM condition for Capybara to wait on. Poll the record instead.
  def assert_low_stock(expected, message = nil)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5

    until @butter.reload.low_stock? == expected || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.1
    end

    assert_equal expected, @butter.reload.low_stock?, message
  end
end
