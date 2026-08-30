require "test_helper"

class GroceryListsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = family_members(:one)
    @member = family_members(:two)
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

  test "admin sees active checkboxes and reset button" do
    get plan_grocery_list_url(@meal_plan)
    assert_response :success
    assert_select "button", text: "Reset"
  end

  test "non-admin member sees disabled checkboxes and no reset button" do
    sign_in_as(@member)
    get plan_grocery_list_url(@meal_plan)
    assert_response :success
    assert_select "button", text: "Reset", count: 0
    assert_select "span", text: "Read-Only"
  end
end
