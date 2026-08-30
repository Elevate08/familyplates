require "test_helper"

class IngredientAisleMappingTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
  end

  test "records usage and increments count" do
    mapping1 = IngredientAisleMapping.record_usage!("Dragon Fruit", "Produce", @household)
    assert_equal 1, mapping1.count
    assert_equal "Produce", mapping1.aisle_category

    mapping2 = IngredientAisleMapping.record_usage!("dragon fruit", "Produce", @household)
    assert_equal mapping1.id, mapping2.id
    assert_equal 2, mapping2.count
  end

  test "returns most likely aisle based on highest weighted count" do
    # 1 count for Bakery, 3 counts for Produce
    IngredientAisleMapping.record_usage!("Special Herb", "Bakery", @household)
    3.times { IngredientAisleMapping.record_usage!("Special Herb", "Produce", @household) }

    assert_equal "Produce", IngredientAisleMapping.most_likely_aisle("Special Herb", @household)
  end

  test "falls back to heuristics when no mapping exists" do
    assert_equal "Produce", IngredientAisleMapping.most_likely_aisle("Fresh Roma Tomatoes", @household)
    assert_equal "Meat & Seafood", IngredientAisleMapping.most_likely_aisle("Ground Sirloin Beef", @household)
    assert_equal "Dairy & Refrigerated", IngredientAisleMapping.most_likely_aisle("Shredded Mozzarella Cheese", @household)
  end

  test "available_ingredients_with_aisles returns list sorted by weight" do
    20.times { IngredientAisleMapping.record_usage!("Popular Chicken", "Meat & Seafood", @household) }

    list = IngredientAisleMapping.available_ingredients_with_aisles(@household)
    assert list.any? { |i| i[:name] == "Popular Chicken" && i[:aisle] == "Meat & Seafood" }
    assert_equal "Popular Chicken", list.first[:name]
  end
end
