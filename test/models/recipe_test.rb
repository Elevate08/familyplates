require "test_helper"

class RecipeTest < ActiveSupport::TestCase
  test "meal_types_list returns array of meal types" do
    recipe = Recipe.new(meal_types: "breakfast,dinner")
    assert_equal [ "breakfast", "dinner" ], recipe.meal_types_list
    assert recipe.for_meal_type?("breakfast")
    assert recipe.for_meal_type?("dinner")
    assert_not recipe.for_meal_type?("lunch")
  end

  test "for_meal_type treats LIKE wildcards as literal text" do
    household = households(:one)
    literal = household.recipes.create!(title: "Percent Meal", meal_types: "100%")
    dinner = household.recipes.create!(title: "Plain Dinner", meal_types: "dinner")

    assert_includes household.recipes.for_meal_type("100%"), literal
    assert_not_includes household.recipes.for_meal_type("%"), dinner
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

  test "rejects an upload the browser would execute" do
    recipe = recipes(:one)
    recipe.image.attach(
      io: StringIO.new("<script>alert(1)</script>"),
      filename: "not-an-image.html",
      content_type: "text/html"
    )

    assert_not recipe.valid?
    assert_includes recipe.errors[:image], "must be a JPEG, PNG, GIF, or WebP"
  end

  test "rejects an image over 8 MB" do
    recipe = recipes(:one)
    recipe.image.attach(
      io: StringIO.new("png"),
      filename: "big.png",
      content_type: "image/png"
    )
    recipe.image.blob.update!(byte_size: Recipe::MAX_IMAGE_BYTES + 1)

    assert_not recipe.valid?
    assert_includes recipe.errors[:image], "must be smaller than 8 MB"
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

  # @card-50.1
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

  # @card-50.1
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

  test "a recipe saved without times keeps them empty" do
    recipe = households(:one).recipes.create!(title: "No Times Given", instructions: "1. Cook.")

    assert_nil recipe.reload.prep_time
    assert_nil recipe.cook_time
  end

  test "total_time is nil when the recipe states no time" do
    recipe = households(:one).recipes.build(title: "Untimed")
    assert_nil recipe.total_time

    recipe.prep_time = 10
    assert_equal 10, recipe.total_time
  end

  test "quick is decided by the quick tag alone, not by prep and cook time" do
    household = households(:one)
    tagged = household.recipes.create!(title: "Tagged Slow Roast", tags: "Quick, Dinner", prep_time: 30, cook_time: 240)
    short_untagged = household.recipes.create!(title: "Short Untagged", tags: "Dinner", prep_time: 5, cook_time: 5)
    untimed = household.recipes.create!(title: "Untimed Untagged")

    quick = household.recipes.quick
    assert_includes quick, tagged
    assert_not_includes quick, short_untagged
    assert_not_includes quick, untimed
  end

  test "blank leftover fields fall back to defaults instead of violating NOT NULL" do
    recipe = households(:one).recipes.create!(title: "Blank Leftovers", instructions: "1. Cook.")
    recipe.update!(leftover_capacity: "", leftover_shelf_life_days: nil)

    assert_equal Recipe::DEFAULT_LEFTOVER_CAPACITY, recipe.reload.leftover_capacity
    assert_equal Recipe::DEFAULT_LEFTOVER_SHELF_LIFE_DAYS, recipe.leftover_shelf_life_days
  end

  test "rejects dangerous URL schemes for source_url and image_url" do
    recipe = households(:one).recipes.build(title: "XSS Test")

    recipe.source_url = "javascript:alert(1)"
    assert_not recipe.valid?
    assert_includes recipe.errors[:source_url], "must be a valid http or https link"

    recipe.source_url = "data:text/html,<script>alert(1)</script>"
    assert_not recipe.valid?
    assert_includes recipe.errors[:source_url], "must be a valid http or https link"

    recipe.source_url = "https://example.com/recipe"
    recipe.image_url = "javascript:alert(2)"
    assert_not recipe.valid?
    assert_includes recipe.errors[:image_url], "must be a valid http or https link"

    recipe.image_url = "data:image/svg+xml;base64,PHN2Zz4="
    assert_not recipe.valid?
    assert_includes recipe.errors[:image_url], "must be a valid http or https link"

    recipe.image_url = "https://example.com/photo.jpg"
    assert recipe.valid?
  end

  test "display_image_url falls back to default if image_url has an unsafe scheme" do
    recipe = Recipe.new(image_url: "javascript:alert(1)")
    assert_includes recipe.display_image_url, "images.unsplash.com"
  end

  test "rejects an upload with non-image extension even if content_type header is forged" do
    recipe = recipes(:one)
    recipe.image.attach(
      io: StringIO.new("<script>alert(1)</script>"),
      filename: "not-an-image.html",
      content_type: "image/jpeg"
    )

    assert_not recipe.valid?
    assert_includes recipe.errors[:image], "must be a JPEG, PNG, GIF, or WebP"
  end

  test "rejects an upload with image extension when content is actually HTML or SVG" do
    recipe = recipes(:one)
    recipe.image.attach(
      io: StringIO.new("<html><body><h1>Hello</h1></body></html>"),
      filename: "fake.jpg",
      content_type: "image/jpeg"
    )

    assert_not recipe.valid?
    assert_includes recipe.errors[:image], "must be a JPEG, PNG, GIF, or WebP"
  end
end
