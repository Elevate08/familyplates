require "test_helper"

class MealPlansControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @meal_plan = meal_plans(:one)
    sign_in_as(@user)
  end

  test "should get index and redirect to current meal plan" do
    get meal_plans_url
    assert_redirected_to meal_plan_url(@meal_plan)
  end

  test "should get show week view" do
    get meal_plan_url(@meal_plan, view: "week")
    assert_response :success
  end

  test "should get show month view" do
    get meal_plan_url(@meal_plan, view: "month")
    assert_response :success
  end

  test "should get print week view" do
    get print_meal_plan_url(@meal_plan, view: "week")
    assert_response :success
  end

  test "should get print month view" do
    get print_meal_plan_url(@meal_plan, view: "month")
    assert_response :success
  end
end
