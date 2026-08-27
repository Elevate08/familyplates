require "test_helper"

class GroceryListsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @meal_plan = meal_plans(:one)
    sign_in_as(@user)
  end

  test "should get current grocery list" do
    get grocery_list_url
    assert_response :success
  end

  test "should get grocery list for specific plan" do
    get plan_grocery_list_url(@meal_plan)
    assert_response :success
  end
end
