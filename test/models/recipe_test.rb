require "test_helper"

class RecipeTest < ActiveSupport::TestCase
  test "meal_types_list returns array of meal types" do
    recipe = Recipe.new(meal_types: "breakfast,dinner")
    assert_equal ["breakfast", "dinner"], recipe.meal_types_list
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
end
