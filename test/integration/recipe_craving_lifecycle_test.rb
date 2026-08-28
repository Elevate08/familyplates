require "test_helper"

class RecipeCravingLifecycleTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @household = households(:one)
    @family_member = family_members(:one)
    @recipe = recipes(:two) # Choose a recipe without existing requests
    @meal_plan = meal_plans(:one)

    RecipeRequest.delete_all
    MealPlanSlot.delete_all

    sign_in_as(@user, family_member: @family_member)
  end

  test "end-to-end craving lifecycle: request -> persist -> schedule -> fulfill -> re-request" do
    # 1. Initially no active requests
    get recipes_url
    assert_response :success
    assert_not @recipe.requested_by?(@family_member)
    assert_equal 0, @recipe.request_count_for_week

    # 2. Member craves the recipe (clicks heart)
    assert_difference("RecipeRequest.count", 1) do
      post recipe_recipe_requests_url(@recipe), as: :turbo_stream
    end
    assert_response :success
    assert @recipe.reload.requested_by?(@family_member)
    assert_equal 1, @recipe.request_count_for_week

    # 3. Recipe appears in 'Cravings' filter on Recipes page
    get recipes_url(filter: "requested")
    assert_response :success
    assert_includes @response.body, @recipe.title

    # 4. Recipe appears in Cravings tray on Meal Planner
    get meal_plan_url(@meal_plan)
    assert_response :success
    assert_includes @response.body, @recipe.title

    # 5. Recipe is scheduled for a FUTURE date (e.g. 2 days from now)
    future_date = Date.current + 2.days
    assert_difference("MealPlanSlot.count", 1) do
      post meal_plan_slots_url, params: {
        meal_plan_id: @meal_plan.id,
        meal_plan_slot: {
          recipe_id: @recipe.id,
          date: future_date,
          meal_type: "dinner"
        }
      }
    end
    assert_response :redirect

    # Craving MUST REMAIN ACTIVE while in the future
    assert @recipe.reload.requested_by?(@family_member)
    assert_equal 1, @recipe.request_count_for_week

    # 6. Date arrives or slot is moved to today/past (indicating the meal was made)
    slot = @meal_plan.meal_plan_slots.last
    patch meal_plan_slot_url(slot), params: {
      meal_plan_slot: {
        date: Date.current,
        meal_type: "dinner",
        recipe_id: @recipe.id
      }
    }
    assert_response :redirect

    # Craving is now FULFILLED and resets to 0!
    assert_not @recipe.reload.requested_by?(@family_member)
    assert_equal 0, @recipe.request_count_for_week

    # Recipe is no longer in 'Cravings' filter
    get recipes_url(filter: "requested")
    assert_response :success
    assert_not_includes @response.body, @recipe.title

    # 7. Member can re-crave the recipe again in the future
    assert_difference("RecipeRequest.count", 1) do
      post recipe_recipe_requests_url(@recipe), as: :turbo_stream
    end
    assert_response :success
    assert @recipe.reload.requested_by?(@family_member)
    assert_equal 1, @recipe.request_count_for_week
  end
end
