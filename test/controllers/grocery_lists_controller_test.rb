require "test_helper"

class GroceryListsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = family_members(:one)
    @meal_plan = meal_plans(:one)
    sign_in_as(@admin)
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
