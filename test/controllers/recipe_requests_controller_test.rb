require "test_helper"

class RecipeRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = family_members(:one)
    @recipe = recipes(:two)
    sign_in_as(@admin)
  end

  test "should create recipe request" do
    assert_difference("RecipeRequest.count", 1) do
      post recipe_recipe_requests_url(@recipe)
    end
    assert_response :redirect
  end

  test "should create recipe request via turbo stream" do
    assert_difference("RecipeRequest.count", 1) do
      post recipe_recipe_requests_url(@recipe), as: :turbo_stream
    end
    assert_response :success
    assert_includes @response.body, "recipe_#{@recipe.id}_heart"
  end

  test "should destroy recipe request via turbo stream" do
    post recipe_recipe_requests_url(@recipe)
    assert_difference("RecipeRequest.count", -1) do
      delete recipe_recipe_request_url(@recipe, "current"), as: :turbo_stream
    end
    assert_response :success
    assert_includes @response.body, "recipe_#{@recipe.id}_heart"
  end
end
