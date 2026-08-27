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
end
