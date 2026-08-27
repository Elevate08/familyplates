require "test_helper"

class RecipeImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "should get new" do
    get new_recipe_import_url
    assert_response :success
  end

  test "should handle blank url" do
    post recipe_imports_url, params: { url: "" }
    assert_redirected_to new_recipe_import_url
  end
end
