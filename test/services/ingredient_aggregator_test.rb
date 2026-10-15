require "test_helper"

class IngredientAggregatorTest < ActiveSupport::TestCase
  test "aggregates ingredients by supermarket aisle and filters pantry staples" do
    meal_plan = meal_plans(:one)
    result = IngredientAggregator.call(meal_plan.household, meal_plan.week_start_date..(meal_plan.week_start_date + 6.days))

    assert result[:aisles].is_a?(Hash)
    assert result[:total_shopping_count] >= 0

    # Ground Beef is in Meat & Seafood and not a pantry staple
    if result[:aisles]["Meat & Seafood"]
      beef = result[:aisles]["Meat & Seafood"].find { |i| i[:name].downcase.include?("ground beef") }
      assert_not_nil beef
    end
  end

  # --- Pantry staple matching -----------------------------------------------
  #
  # This ran a substring comparison in *both* directions, so anything containing
  # a staple's name - or contained by it - counted as already in the pantry and
  # was dropped from the shopping list. The table below is the record of what
  # that cost against the stock staple list, and of the trade-off in the fix.

  STOCK_STAPLES = %w[
    Salt Butter Rice Pasta Garlic Onions Eggs
  ].freeze

  # Every one of these contains a staple's name. None of them is that staple.
  NOT_IN_PANTRY = [
    "Butternut squash",
    "Buttermilk",
    "Peanut butter",
    "Salted butter",
    "Rice vinegar",
    "Rice noodles",
    "Pasta sauce",
    "Garlic bread",
    "Green onions",
    "Brown rice"
  ].freeze

  def aggregate_with_staples(ingredient_names, staple_names: STOCK_STAPLES)
    household = Household.create!(name: "Matching Test Kitchen")
    staple_names.each do |name|
      household.pantry_items.create!(name: name, aisle_category: "Other", is_staple: true)
    end

    recipe = household.recipes.create!(title: "Everything Casserole", instructions: "Combine.")
    ingredient_names.each { |name| recipe.recipe_ingredients.create!(name: name, aisle_category: "Other") }

    plan = household.meal_plans.create!(week_start_date: Date.new(2026, 2, 2))
    plan.meal_plan_slots.create!(date: Date.new(2026, 2, 2), meal_type: "dinner", recipe: recipe)

    IngredientAggregator.call(plan.household, plan.week_start_date..(plan.week_start_date + 6.days))[:aisles].values.flatten.index_by { |item| item[:name].downcase }
  end

  test "an ingredient that merely contains a staple's name is still on the shopping list" do
    items = aggregate_with_staples(NOT_IN_PANTRY)

    NOT_IN_PANTRY.each do |name|
      item = items[name.downcase]
      assert_not_nil item, "#{name} vanished from the list entirely"
      assert_not item[:is_staple], "#{name} was wrongly treated as already in the pantry"
    end
  end

  test "an exact staple match is still recognised, case and plural insensitively" do
    items = aggregate_with_staples([ "Salt", "  butter  ", "RICE", "Egg", "Onion" ])

    assert items["salt"][:is_staple]
    assert items["butter"][:is_staple], "surrounding whitespace must not matter"
    assert items["rice"][:is_staple], "case must not matter"
    assert items["egg"][:is_staple], "an ingredient \"Egg\" is the staple \"Eggs\""
    assert items["onion"][:is_staple], "an ingredient \"Onion\" is the staple \"Onions\""
  end

  test "accepted regression: a more specific ingredient no longer matches a broader staple" do
    # "Kosher salt" is salt, and under the old substring rule it matched. Exact
    # matching gives that up on purpose - see the asymmetry note in the service.
    # The cost is one extra line on a shopping list; a user who wants it matched
    # can add "Kosher salt" to their pantry.
    items = aggregate_with_staples([ "Kosher salt" ])

    assert_not items["kosher salt"][:is_staple]
  end

  test "a staple the household actually added is matched" do
    items = aggregate_with_staples([ "Kosher salt" ], staple_names: [ "Kosher Salt" ])

    assert items["kosher salt"][:is_staple]
  end

  # --- Date ranges ------------------------------------------------------------

  def range_household
    @range_household ||= Household.create!(name: "Range Kitchen")
  end

  def range_recipe(title, ingredients, household: range_household)
    household.recipes.create!(title: title, instructions: "Cook.").tap do |recipe|
      ingredients.each do |name, qty|
        recipe.recipe_ingredients.create!(name: name, quantity: qty, unit: "cup", aisle_category: "Produce")
      end
    end
  end

  def plan_slot(date, meal_type, recipe, household: range_household, **attrs)
    plan = household.current_meal_plan(date.beginning_of_week)
    plan.meal_plan_slots.create!(date: date, meal_type: meal_type, recipe: recipe, **attrs)
  end

  def items_for(range, household: range_household)
    result = IngredientAggregator.call(household, range)
    [ result, result[:aisles].values.flatten.index_by { |item| item[:name].downcase } ]
  end

  # @card-62.3
  test "a recipe planned on two days counts its ingredients twice" do
    soup = range_recipe("Soup", { "Carrots" => 2 })
    plan_slot(Date.new(2026, 10, 19), "dinner", soup)
    plan_slot(Date.new(2026, 10, 21), "dinner", soup)

    _result, items = items_for(Date.new(2026, 10, 19)..Date.new(2026, 10, 25))

    assert_equal 4, items["carrots"][:quantity]
  end

  # @card-62.1
  test "a range can span two meal plans and a month boundary" do
    soup = range_recipe("Soup", { "Carrots" => 1 })
    plan_slot(Date.new(2026, 10, 30), "dinner", soup)
    plan_slot(Date.new(2026, 11, 2), "dinner", soup)
    plan_slot(Date.new(2026, 11, 20), "dinner", soup)

    result, items = items_for(Date.new(2026, 10, 29)..Date.new(2026, 11, 4))

    assert_equal 2, items["carrots"][:quantity]
    assert_equal 2, result[:meal_count]
  end

  test "slots outside the range are left out" do
    soup = range_recipe("Soup", { "Carrots" => 1 })
    plan_slot(Date.new(2026, 10, 18), "dinner", soup)
    plan_slot(Date.new(2026, 10, 26), "dinner", soup)

    result, items = items_for(Date.new(2026, 10, 19)..Date.new(2026, 10, 25))

    assert_empty items
    assert_equal 0, result[:meal_count]
  end

  test "a leftover slot does not buy the recipe again" do
    soup = range_recipe("Soup", { "Carrots" => 1 })
    cooked = plan_slot(Date.new(2026, 10, 19), "dinner", soup)
    plan_slot(Date.new(2026, 10, 20), "lunch", soup, is_leftover: true, leftover_source_slot: cooked)

    _result, items = items_for(Date.new(2026, 10, 19)..Date.new(2026, 10, 25))

    assert_equal 1, items["carrots"][:quantity]
  end

  # @card-62.6
  test "another household's slots are never included" do
    soup = range_recipe("Soup", { "Carrots" => 1 })
    plan_slot(Date.new(2026, 10, 19), "dinner", soup)
    other = Household.create!(name: "Other Kitchen")
    secret = range_recipe("Secret", { "Truffles" => 1 }, household: other)
    plan_slot(Date.new(2026, 10, 19), "lunch", secret, household: other)

    result, items = items_for(Date.new(2026, 10, 19)..Date.new(2026, 10, 25))

    assert_not items.key?("truffles")
    assert_equal 1, result[:meal_count]
  end

  test "a low staple nobody cooks with appears once, however many days the range has" do
    range_household.pantry_items.create!(name: "Salt", aisle_category: "Spices & Baking", is_staple: true, low_stock_at: Time.current)
    soup = range_recipe("Soup", { "Carrots" => 1 })
    plan_slot(Date.new(2026, 10, 19), "dinner", soup)
    plan_slot(Date.new(2026, 10, 20), "dinner", soup)

    result, _items = items_for(Date.new(2026, 10, 19)..Date.new(2026, 10, 25))

    assert_equal 1, result[:aisles].values.flatten.count { |item| item[:name] == "Salt" }
    assert_equal 1, result[:total_restock_count]
  end
end
