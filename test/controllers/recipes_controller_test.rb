require "test_helper"

class RecipesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = family_members(:one)
    @recipe = recipes(:one)
    sign_in_as(@admin)
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

  test "should filter by tag" do
    get recipes_url(tag: "Mexican")
    assert_response :success
    get recipes_url(filter: "tag:Mexican")
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
    assert_equal [ "breakfast" ], created.meal_types_list
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
      recipe_ids: [ r1.id, r2.id ],
      update_meal_types: "1",
      meal_types: [ "breakfast", "lunch" ]
    }

    assert_redirected_to recipes_url
    assert_equal [ "breakfast", "lunch" ], r1.reload.meal_types_list
    assert_equal [ "breakfast", "lunch" ], r2.reload.meal_types_list
  end

  test "should bulk update tags" do
    r1 = recipes(:one)
    r2 = recipes(:two)

    post bulk_update_recipes_url, params: {
      recipe_ids: [ r1.id, r2.id ],
      update_tags: "1",
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
        recipe_ids: [ r1.id, r2.id ]
      }
    end

    assert_redirected_to recipes_url
  end

  test "non-admin member should not be able to edit recipe" do
    sign_in_as(family_members(:two)) # Mom (role: member)

    get edit_recipe_url(@recipe)
    assert_redirected_to root_url
    assert_equal "Access restricted to household organizers / admins.", flash[:alert]
  end

  test "non-admin member should not be able to update recipe" do
    sign_in_as(family_members(:two)) # Mom (role: member)

    patch recipe_url(@recipe), params: {
      recipe: { title: "Hacked Title" }
    }
    assert_redirected_to root_url
    assert_not_equal "Hacked Title", @recipe.reload.title
  end

  test "non-admin member should not be able to destroy recipe" do
    sign_in_as(family_members(:two)) # Mom (role: member)

    assert_no_difference("Recipe.count") do
      delete recipe_url(@recipe)
    end
    assert_redirected_to root_url
  end

  test "non-admin member should not be able to bulk update recipes" do
    sign_in_as(family_members(:two)) # Mom (role: member)

    post bulk_update_recipes_url, params: {
      recipe_ids: [ @recipe.id ],
      update_meal_types: "1",
      meal_types: [ "breakfast" ]
    }
    assert_redirected_to root_url
  end

  test "non-admin member should not be able to bulk destroy recipes" do
    sign_in_as(family_members(:two)) # Mom (role: member)

    assert_no_difference("Recipe.count") do
      post bulk_destroy_recipes_url, params: {
        recipe_ids: [ @recipe.id ]
      }
    end
    assert_redirected_to root_url
  end

  # --- Ingredient catalogue payload -------------------------------------------
  #
  # The catalogue is 150+ default staples plus every household ingredient. It was
  # emitted into a data attribute on every ingredient row, so a twenty-ingredient
  # recipe shipped twenty identical copies of it.

  test "the recipe form emits the ingredient catalogue exactly once" do
    sign_in_as(@admin)
    recipe = households(:one).recipes.create!(title: "Many Ingredients", instructions: "x")
    12.times { |i| recipe.recipe_ingredients.create!(name: "Ingredient #{i}") }

    get edit_recipe_url(recipe)
    assert_response :success

    # Thirteen: the twelve saved rows plus the hidden <template> row the add
    # button clones. Each of those used to carry its own copy of the catalogue.
    assert_equal 13, response.body.scan(/data-ingredient-row="true"/).length,
      "precondition: twelve rows plus the add-row template"
    assert_equal 1, response.body.scan(/data-ingredient-catalogue-ingredients=/).length,
      "the catalogue must be emitted once on the container, not once per row"
    assert_equal 1, response.body.scan(/data-ingredient-catalogue-units=/).length
    assert_equal 0, response.body.scan(/data-ingredient-autofill-ingredients-value=/).length,
      "no row should still carry its own copy"
  end

  test "the import failure page does not query for the catalogue per row" do
    sign_in_as(@admin)

    queries = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      queries += 1 if args.last[:sql].to_s.include?("ingredient_aisle_mappings")
    end
    post recipe_imports_url, params: { url: "http://169.254.169.254/blocked" }
    ActiveSupport::Notifications.unsubscribe(sub)

    assert_operator queries, :<=, 2,
      "#{queries} catalogue queries - the failure path should load it once, not per row"
  end
end
