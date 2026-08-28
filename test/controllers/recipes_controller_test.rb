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

  test "should filter by meal type" do
    get recipes_url(filter: "breakfast")
    assert_response :success
    get recipes_url(filter: "lunch")
    assert_response :success
    get recipes_url(filter: "dinner")
    assert_response :success
  end

  test "should get show with meal planning form" do
    get recipe_url(@recipe)
    assert_response :success
    assert_includes response.body, "Schedule"
    assert_includes response.body, "meal_plan_slot[date]"
    assert_includes response.body, "meal_plan_slot[meal_type]"
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

  test "should create recipe with meal types and image upload" do
    file = fixture_file_upload("files/test_image.png", "image/png") rescue Rack::Test::UploadedFile.new(StringIO.new("img content"), "image/png", original_filename: "test.png")

    assert_difference("Recipe.count", 1) do
      post recipes_url, params: {
        recipe: {
          title: "Blueberry French Toast",
          meal_types: "breakfast",
          image: file
        }
      }
    end

    created = Recipe.last
    assert_equal "Blueberry French Toast", created.title
    assert_equal ["breakfast"], created.meal_types_list
    assert created.image.attached?
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

  test "should get index with list view" do
    get recipes_url(view: "list")
    assert_response :success
    assert_includes response.body, "#{dom_id(recipes(:one))}_row"
  end

  test "should bulk update meal types" do
    r1 = recipes(:one)
    r2 = recipes(:two)

    post bulk_update_recipes_url, params: {
      recipe_ids: [r1.id, r2.id],
      meal_types_mode: "set",
      meal_types: ["breakfast", "lunch"]
    }

    assert_redirected_to recipes_url
    assert_equal ["breakfast", "lunch"], r1.reload.meal_types_list
    assert_equal ["breakfast", "lunch"], r2.reload.meal_types_list
  end

  test "should bulk update tags" do
    r1 = recipes(:one)
    r2 = recipes(:two)

    post bulk_update_recipes_url, params: {
      recipe_ids: [r1.id, r2.id],
      tags_mode: "add",
      tags: "Family Favorite, Weekend Grill"
    }

    assert_redirected_to recipes_url
    assert_includes r1.reload.tag_list, "Family Favorite"
    assert_includes r2.reload.tag_list, "Weekend Grill"
  end

  test "should bulk destroy recipes" do
    r1 = recipes(:one)
    r2 = recipes(:two)

    assert_difference("Recipe.count", -2) do
      post bulk_destroy_recipes_url, params: {
        recipe_ids: [r1.id, r2.id]
      }
    end

    assert_redirected_to recipes_url
  end
end
