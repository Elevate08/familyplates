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

  test "should get print month view with all meal types clearly labeled" do
    test_date = @meal_plan.week_start_date + 4.days
    @meal_plan.meal_plan_slots.create!(date: test_date, meal_type: "breakfast", custom_title: "Blueberry Oatmeal")
    @meal_plan.meal_plan_slots.create!(date: test_date, meal_type: "lunch", custom_title: "Turkey Sandwich")
    @meal_plan.meal_plan_slots.create!(date: test_date, meal_type: "dinner", custom_title: "Spaghetti Bolognese")

    get print_meal_plan_url(@meal_plan, view: "month")
    assert_response :success
    assert_includes response.body, "Blueberry Oatmeal"
    assert_includes response.body, "Turkey Sandwich"
    assert_includes response.body, "Spaghetti Bolognese"
    assert_includes response.body, "B:"
    assert_includes response.body, "L:"
    assert_includes response.body, "D:"
  end
end
