require "test_helper"

# /cook is the kitchen display's one-tap entry: it reads the clock, works out
# which planned meal is on the stove, and opens Cook Mode on it.
class CookNowTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @admin = family_members(:one)
    @member = family_members(:two)
    @household.update!(breakfast_time: "08:00", lunch_time: "12:30", dinner_time: "18:00")
    @plan = @household.current_meal_plan(Date.current.beginning_of_week)

    @pancakes = @household.recipes.create!(title: "Buttermilk Pancakes", instructions: "1. Griddle them.")
    @ribs = @household.recipes.create!(title: "Braised Short Ribs", instructions: "1. Braise them.")
  end

  def plan_meal(meal_type, recipe, date: Date.current, scheduled_time: nil)
    @plan.meal_plan_slots.create!(
      date: date, meal_type: meal_type, recipe: recipe, scheduled_time: scheduled_time
    )
  end

  def at(hour, minute = 0)
    Time.zone.local(Date.current.year, Date.current.month, Date.current.day, hour, minute, 0)
  end

  test "opens the meal whose cooking window is open" do
    plan_meal("breakfast", @pancakes)
    plan_meal("dinner", @ribs)

    sign_in_as(@admin)

    travel_to at(16, 30) do
      get cook_now_url
      assert_redirected_to cook_recipe_path(@ribs)
    end

    travel_to at(7, 0) do
      get cook_now_url
      assert_redirected_to cook_recipe_path(@pancakes)
    end
  end

  test "falls back to the day's nearest planned meal when no window is open" do
    plan_meal("breakfast", @pancakes)
    plan_meal("dinner", @ribs)

    sign_in_as(@admin)

    # 10am: breakfast is over, dinner is hours off - but dinner is what is left.
    travel_to at(10, 0) do
      get cook_now_url
      assert_redirected_to cook_recipe_path(@ribs)
    end
  end

  test "says nothing is planned, and offers what is coming, when today is empty" do
    plan_meal("dinner", @ribs, date: Date.current + 2)

    sign_in_as(@admin)
    get cook_now_url

    assert_response :success
    assert_select "nav", false, "the empty state renders in the cook layout"
    assert_includes response.body, "Nothing is planned"
    assert_select "a[href=?]", cook_recipe_path(@ribs)
  end

  test "an empty plan still offers a way to the meal plan and the recipe box" do
    sign_in_as(@admin)
    get cook_now_url

    assert_response :success
    assert_select "a[href=?]", meal_plans_path
    assert_select "a[href=?]", recipes_path
  end

  test "the meal plan banner names the meal on the stove and links to cook mode" do
    plan_meal("dinner", @ribs)
    sign_in_as(@admin)

    travel_to at(17, 0) do
      get meal_plan_url(@plan)

      assert_response :success
      assert_includes response.body, "Cooking now"
      assert_includes response.body, "Braised Short Ribs"
      assert_select "a[href=?]", cook_now_path
    end
  end

  test "the banner says up next when no window is open" do
    plan_meal("dinner", @ribs)
    sign_in_as(@admin)

    travel_to at(9, 0) do
      get meal_plan_url(@plan)

      assert_includes response.body, "Up next"
      assert_not_includes response.body, "Cooking now"
    end
  end

  test "the banner stays away rather than sitting there dead with nothing planned" do
    sign_in_as(@admin)
    get meal_plan_url(@plan)

    assert_response :success
    assert_select "a[href=?]", cook_now_path, false
  end

  test "a member who cannot edit the plan can still cook from it" do
    plan_meal("dinner", @ribs)
    sign_in_as(@member)
    assert_not @member.admin?

    travel_to at(17, 0) do
      get cook_now_url
      assert_redirected_to cook_recipe_path(@ribs)
    end
  end

  # The whole point of recording a zone: a UTC server deciding what is on the
  # stove in a Chicago kitchen.
  test "opens the right meal for a household that is not on UTC" do
    @household.update!(time_zone: "America/Chicago")
    dinner_date = Date.new(2026, 9, 5)
    @plan = @household.current_meal_plan(dinner_date.beginning_of_week)
    @plan.meal_plan_slots.create!(date: dinner_date, meal_type: "dinner", recipe: @ribs)

    sign_in_as(@admin)

    # 23:00 UTC is 6pm in the kitchen - dinner time.
    travel_to Time.utc(2026, 9, 5, 23, 0, 0) do
      get cook_now_url
      assert_redirected_to cook_recipe_path(@ribs)
    end

    # 18:00 UTC is 1pm there: too early for dinner's window, but dinner is still
    # the day's next planned meal, so it is what the button offers.
    travel_to Time.utc(2026, 9, 5, 18, 0, 0) do
      get cook_now_url
      assert_redirected_to cook_recipe_path(@ribs)
    end
  end

  test "another household's planned meal is never opened" do
    other = households(:two)
    other_plan = other.current_meal_plan(Date.current.beginning_of_week)
    other_plan.meal_plan_slots.create!(
      date: Date.current, meal_type: "dinner",
      recipe: other.recipes.create!(title: "Not Yours", instructions: "1. Cook.")
    )

    sign_in_as(@admin)

    travel_to at(17, 0) do
      get cook_now_url
      assert_response :success
      assert_not_includes response.body, "Not Yours"
    end
  end
end
