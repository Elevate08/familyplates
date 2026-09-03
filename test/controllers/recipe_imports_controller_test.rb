require "test_helper"

class RecipeImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = family_members(:one)
    sign_in_as(@admin)
  end

  test "should get new" do
    get new_recipe_import_url
    assert_response :success
  end

  test "should handle blank url" do
    post recipe_imports_url, params: { url: "" }
    assert_redirected_to new_recipe_import_url
  end

  test "should import recipe and redirect to recipe show page" do
    scraped_data = {
      title: "French Toast Casserole",
      description: "Delicious breakfast casserole",
      prep_time: 15,
      cook_time: 45,
      servings: 6,
      source_url: "https://www.allrecipes.com/recipe/22389/french-toast-casserole/",
      instructions: "1. Line pan with bread.\n2. Bake.",
      ingredients: [
        { raw_text: "5 cups bread cubes", name: "Bread cubes", quantity: 5.0, unit: "cups", aisle_category: "Bakery" }
      ]
    }

    original_call = RecipeScraper.method(:call)
    RecipeScraper.define_singleton_method(:call) { |_url| scraped_data }

    begin
      assert_difference("Recipe.count", 1) do
        post recipe_imports_url, params: { url: "https://www.allrecipes.com/recipe/22389/french-toast-casserole/" }
      end
      recipe = Recipe.last
      assert_redirected_to edit_recipe_url(recipe)
      assert_equal "French Toast Casserole", recipe.title
      assert_equal 1, recipe.recipe_ingredients.count
      assert_includes flash[:notice], "Imported"
    ensure
      RecipeScraper.define_singleton_method(:call, original_call)
    end
  end

  test "should redirect with alert if recipe URL already imported" do
    recipes(:one).update!(source_url: "https://example.com/existing-tacos")

    post recipe_imports_url, params: { url: "https://example.com/existing-tacos" }
    assert_redirected_to recipe_url(recipes(:one))
    assert_includes flash[:alert], "already saved as"
  end

  test "should redirect with alert if recipe title already exists" do
    scraped_data = {
      title: recipes(:one).title,
      description: "Another taco",
      prep_time: 15,
      cook_time: 20,
      servings: 4,
      source_url: "https://example.com/different-tacos",
      instructions: "Cook.",
      ingredients: []
    }

    original_call = RecipeScraper.method(:call)
    RecipeScraper.define_singleton_method(:call) { |_url| scraped_data }

    begin
      assert_no_difference("Recipe.count") do
        post recipe_imports_url, params: { url: "https://example.com/different-tacos" }
      end
      assert_redirected_to recipe_url(recipes(:one))
      assert_includes flash[:alert], "already in your recipe box"
    ensure
      RecipeScraper.define_singleton_method(:call, original_call)
    end
  end

  test "a blocked import URL is refused with the ordinary error and creates nothing" do
    assert_no_difference "Recipe.count" do
      post recipe_imports_url, params: { url: "http://169.254.169.254/latest/meta-data/" }
    end

    assert_redirected_to new_recipe_import_url
    assert_equal "Could not fetch recipe from that web address. Please check the link or add manually.", flash[:alert]
  end
end
