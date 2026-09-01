require "test_helper"

class IngredientAggregatorTest < ActiveSupport::TestCase
  test "aggregates ingredients by supermarket aisle and filters pantry staples" do
    meal_plan = meal_plans(:one)
    result = IngredientAggregator.call(meal_plan)

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

    IngredientAggregator.call(plan)[:aisles].values.flatten.index_by { |item| item[:name].downcase }
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
end
