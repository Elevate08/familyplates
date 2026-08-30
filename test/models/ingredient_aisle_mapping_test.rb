require "test_helper"

class IngredientAisleMappingTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
    @recipe = recipes(:one)
  end

  test "syncs ingredient usage accurately to actual recipes in database" do
    # When a recipe ingredient is added, count is 1
    ing = @recipe.recipe_ingredients.create!(name: "Dragon Fruit", quantity: 1, unit: "piece", aisle_category: "Produce")
    mapping = IngredientAisleMapping.find_by(household: @household, name: "dragon fruit")
    assert_not_nil mapping
    assert_equal 1, mapping.count

    # Editing the same recipe ingredient 5 times does NOT artificially increment the count
    5.times do
      ing.update!(quantity: 2)
    end
    mapping.reload
    assert_equal 1, mapping.count

    # Adding another recipe with the same ingredient increments to 2
    recipe2 = recipes(:two)
    recipe2.recipe_ingredients.create!(name: "Dragon Fruit", quantity: 3, unit: "pieces", aisle_category: "Produce")
    mapping.reload
    assert_equal 2, mapping.count

    # Deleting one recipe ingredient decrements back to 1
    ing.destroy
    mapping.reload
    assert_equal 1, mapping.count
  end

  test "returns most likely aisle based on highest weighted count" do
    recipe1 = recipes(:one)
    recipe2 = recipes(:two)

    # 1 recipe has "Special Herb" in Bakery, 2 recipes have it in Produce
    recipe1.recipe_ingredients.create!(name: "Special Herb", quantity: 1, aisle_category: "Bakery")
    recipe2.recipe_ingredients.create!(name: "Special Herb", quantity: 1, aisle_category: "Produce")
    @household.recipes.create!(title: "Herb Salad", recipe_ingredients_attributes: [ { name: "Special Herb", quantity: 1, aisle_category: "Produce" } ])

    assert_equal "Produce", IngredientAisleMapping.most_likely_aisle("Special Herb", @household)
  end

  test "falls back to heuristics when no mapping exists" do
    assert_equal "Produce", IngredientAisleMapping.most_likely_aisle("Fresh Roma Tomatoes", @household)
    assert_equal "Meat & Seafood", IngredientAisleMapping.most_likely_aisle("Ground Sirloin Beef", @household)
    assert_equal "Dairy & Refrigerated", IngredientAisleMapping.most_likely_aisle("Shredded Mozzarella Cheese", @household)
  end

  test "available_ingredients_with_aisles returns list sorted by weight" do
    # Seed high count in household
    50.times do |i|
      r = @household.recipes.create!(title: "Chicken Recipe #{i}")
      r.recipe_ingredients.create!(name: "Super Chicken", aisle_category: "Meat & Seafood", quantity: 1)
    end

    list = IngredientAisleMapping.available_ingredients_with_aisles(@household)
    assert list.any? { |i| i[:name] == "Super Chicken" && i[:aisle] == "Meat & Seafood" }
    assert_equal "Super Chicken", list.first[:name]
  end
end
