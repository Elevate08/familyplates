require "test_helper"

class RecipeRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @recipe = recipes(:two)
    sign_in_as(@user)
  end

  test "should create recipe request" do
    assert_difference("RecipeRequest.count", 1) do
      post recipe_recipe_requests_url(@recipe)
    end
    assert_response :redirect
  end

  test "should destroy recipe request" do
    # Create request first
    post recipe_recipe_requests_url(@recipe)
    assert_difference("RecipeRequest.count", -1) do
      delete recipe_recipe_request_url(@recipe, "current")
    end
    assert_response :redirect
  end
end
