require "test_helper"

class RecipesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @recipe = recipes(:one)
    sign_in_as(@user)
  end

  test "should get index" do
    get recipes_url
    assert_response :success
  end

  test "should filter by quick recipes" do
    get recipes_url(filter: "quick")
    assert_response :success
  end

  test "should filter by cravings" do
    get recipes_url(filter: "requested")
    assert_response :success
  end

  test "should get show" do
    get recipe_url(@recipe)
    assert_response :success
  end

  test "should get new" do
    get new_recipe_url
    assert_response :success
  end

  test "should create recipe" do
    assert_difference("Recipe.count", 1) do
      post recipes_url, params: {
        recipe: {
          title: "Lemon Herb Salmon",
          prep_time: 10,
          cook_time: 15,
          servings: 4,
          instructions: "Bake at 400F.",
          tags: "Healthy, Seafood",
          recipe_ingredients_attributes: [
            { raw_text: "4 salmon fillets", name: "Salmon", quantity: 4, unit: "fillets", aisle_category: "Meat & Seafood" }
          ]
        }
      }
    end

    assert_redirected_to recipe_url(Recipe.last)
  end

  test "should update recipe" do
    patch recipe_url(@recipe), params: {
      recipe: { title: "Super Taco Tuesday" }
    }
    assert_redirected_to recipe_url(@recipe)
    assert_equal "Super Taco Tuesday", @recipe.reload.title
  end

  test "should destroy recipe" do
    assert_difference("Recipe.count", -1) do
      delete recipe_url(@recipe)
    end
    assert_redirected_to recipes_url
  end
end
