require "test_helper"

class RecipeIngredientTest < ActiveSupport::TestCase
  setup do
    @recipe = recipes(:one)
  end

  test "automatically resolves aisle category from mapping if blank" do
    ingredient = @recipe.recipe_ingredients.build(name: "Fresh Garlic", raw_text: "2 cloves fresh garlic", quantity: 2, unit: "cloves")
    ingredient.valid?
    assert_equal "Produce", ingredient.aisle_category
  end

  test "records usage in IngredientAisleMapping on save" do
    assert_difference -> { IngredientAisleMapping.count }, 1 do
      @recipe.recipe_ingredients.create!(name: "Dragon Fruit", quantity: 1, unit: "piece", aisle_category: "Produce")
    end

    mapping = IngredientAisleMapping.find_by(name: "dragon fruit", household: @recipe.household)
    assert_not_nil mapping
    assert_equal "Produce", mapping.aisle_category
  end

  test "formats display quantity without trailing zeros" do
    i1 = RecipeIngredient.new(quantity: 2.0)
    assert_equal "2", i1.display_quantity

    i2 = RecipeIngredient.new(quantity: 1.5)
    assert_equal "1.5", i2.display_quantity
  end
end
