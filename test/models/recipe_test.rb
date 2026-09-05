require "test_helper"

class RecipeTest < ActiveSupport::TestCase
  test "meal_types_list returns array of meal types" do
    recipe = Recipe.new(meal_types: "breakfast,dinner")
    assert_equal [ "breakfast", "dinner" ], recipe.meal_types_list
    assert recipe.for_meal_type?("breakfast")
    assert recipe.for_meal_type?("dinner")
    assert_not recipe.for_meal_type?("lunch")
  end

  test "for_meal_type scope filters recipes by meal type" do
    household = households(:one)
    breakfast_recipe = household.recipes.create!(title: "Pancakes", meal_types: "breakfast")
    dinner_recipe = household.recipes.create!(title: "Steak", meal_types: "dinner")
    all_day_recipe = household.recipes.create!(title: "Sandwich", meal_types: "breakfast,lunch,dinner")

    breakfast_results = household.recipes.for_meal_type("breakfast")
    assert_includes breakfast_results, breakfast_recipe
    assert_includes breakfast_results, all_day_recipe
    assert_not_includes breakfast_results, dinner_recipe

    dinner_results = household.recipes.for_meal_type("dinner")
    assert_includes dinner_results, dinner_recipe
    assert_includes dinner_results, all_day_recipe
    assert_not_includes dinner_results, breakfast_recipe
  end

  test "display_image_url returns image_url when present" do
    recipe = Recipe.new(image_url: "https://example.com/test.jpg")
    assert_equal "https://example.com/test.jpg", recipe.display_image_url
  end

  test "supports image attachment" do
    recipe = recipes(:one)
    recipe.image.attach(
      io: StringIO.new("fake image data"),
      filename: "test.png",
      content_type: "image/png"
    )
    assert recipe.image.attached?
  end

  test "yields_leftovers flag and leftover_friendly scope" do
    household = households(:one)
    batch_recipe = household.recipes.create!(title: "Big Lasagna", yields_leftovers: true)
    quick_recipe = household.recipes.create!(title: "Quick Toast", yields_leftovers: false)

    assert batch_recipe.yields_leftovers?
    assert_not quick_recipe.yields_leftovers?

    assert_includes household.recipes.leftover_friendly, batch_recipe
    assert_not_includes household.recipes.leftover_friendly, quick_recipe
  end

  test "leftover capacity and shelf life have sensible defaults and effective fallbacks" do
    recipe = Recipe.new
    assert_equal 1, recipe.leftover_capacity
    assert_equal 3, recipe.leftover_shelf_life_days
    assert_equal 1, recipe.effective_leftover_capacity
    assert_equal 3, recipe.effective_leftover_shelf_life_days

    recipe.leftover_capacity = nil
    recipe.leftover_shelf_life_days = nil
    assert_equal 1, recipe.effective_leftover_capacity
    assert_equal 3, recipe.effective_leftover_shelf_life_days
  end

  test "validates leftover capacity between 1 and 10" do
    household = households(:one)
    recipe = household.recipes.build(title: "Soup")

    recipe.leftover_capacity = 0
    assert_not recipe.valid?
    assert_includes recipe.errors[:leftover_capacity], "must be greater than or equal to 1"

    recipe.leftover_capacity = 11
    assert_not recipe.valid?
    assert_includes recipe.errors[:leftover_capacity], "must be less than or equal to 10"

    recipe.leftover_capacity = 5
    assert recipe.valid?
  end

  test "validates leftover shelf life between 1 and 14" do
    household = households(:one)
    recipe = household.recipes.build(title: "Fish Stew")

    recipe.leftover_shelf_life_days = 0
    assert_not recipe.valid?
    assert_includes recipe.errors[:leftover_shelf_life_days], "must be greater than or equal to 1"

    recipe.leftover_shelf_life_days = 15
    assert_not recipe.valid?
    assert_includes recipe.errors[:leftover_shelf_life_days], "must be less than or equal to 14"

    recipe.leftover_shelf_life_days = 7
    assert recipe.valid?
  end
end
