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

  test "should get print week view with 4-column matrix containing Breakfast, Lunch, Dinner with equal prominence" do
    thursday = @meal_plan.week_start_date + 3.days
    member = family_members(:one)
    @meal_plan.meal_plan_slots.create!(date: thursday, meal_type: "breakfast", custom_title: "Avocado Toast", family_member: member)
    @meal_plan.meal_plan_slots.create!(date: thursday, meal_type: "lunch", custom_title: "Chicken Salad Wrap", family_member: member)
    @meal_plan.meal_plan_slots.create!(date: thursday, meal_type: "dinner", custom_title: "Grilled Salmon", family_member: member)

    get print_meal_plan_url(@meal_plan, view: "week")
    assert_response :success
    assert_includes response.body, "Breakfast"
    assert_includes response.body, "Lunch"
    assert_includes response.body, "Dinner"
    assert_includes response.body, "Avocado Toast"
    assert_includes response.body, "Chicken Salad Wrap"
    assert_includes response.body, "Grilled Salmon"
    assert_includes response.body, member.name
    assert_includes response.body, "size: landscape"
  end

  test "should get print month view with all meal types clearly labeled" do
    test_date = @meal_plan.week_start_date + 4.days
    member = family_members(:one)
    @meal_plan.meal_plan_slots.create!(date: test_date, meal_type: "breakfast", custom_title: "Blueberry Oatmeal", family_member: member)
    @meal_plan.meal_plan_slots.create!(date: test_date, meal_type: "lunch", custom_title: "Turkey Sandwich", family_member: member)
    @meal_plan.meal_plan_slots.create!(date: test_date, meal_type: "dinner", custom_title: "Spaghetti Bolognese", family_member: member)

    get print_meal_plan_url(@meal_plan, view: "month")
    assert_response :success
    assert_includes response.body, "Blueberry Oatmeal"
    assert_includes response.body, "Turkey Sandwich"
    assert_includes response.body, "Spaghetti Bolognese"
    assert_includes response.body, member.name
    assert_includes response.body, "size: landscape"
  end
end
