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

  test "should get show month view showing only days of the current month with full titles" do
    wednesday = @meal_plan.week_start_date + 2.days
    @meal_plan.meal_plan_slots.create!(date: wednesday, meal_type: "dinner", custom_title: "Slow-Cooker Beef Bourguignon with Egg Noodles and Green Peas")

    get meal_plan_url(@meal_plan, view: "month", month: wednesday.strftime("%Y-%m-01"))
    assert_response :success

    assert_includes response.body, "Slow-Cooker Beef Bourguignon with Egg Noodles and Green Peas"
  end

  test "should get print week view with clean centered layout, columns as days, rows as meals, no icons, no background colors, and cook/time on bottom" do
    thursday = @meal_plan.week_start_date + 3.days
    member = family_members(:one)
    recipe = recipes(:one)
    @meal_plan.meal_plan_slots.create!(date: thursday, meal_type: "breakfast", custom_title: "Avocado Toast with Poached Eggs and Fresh Herbs", family_member: member)
    @meal_plan.meal_plan_slots.create!(date: thursday, meal_type: "lunch", custom_title: "Chicken Salad Wrap", family_member: member)
    @meal_plan.meal_plan_slots.create!(date: thursday, meal_type: "dinner", recipe: recipe, family_member: member)

    get print_meal_plan_url(@meal_plan, view: "week")
    assert_response :success
    assert_includes response.body, "Breakfast"
    assert_includes response.body, "Lunch"
    assert_includes response.body, "Dinner"
    assert_includes response.body, "Avocado Toast with Poached Eggs and Fresh Herbs"
    assert_includes response.body, "Chicken Salad Wrap"
    assert_includes response.body, recipe.title
    assert_includes response.body, member.name
    assert_includes response.body, "#{recipe.total_time} mins"
    assert_includes response.body, "size: letter landscape"
    assert_not_includes response.body, "portrait"

    # Cook: and Time: in distinct colors
    assert_select "span.text-blue-700", text: "Cook:"
    assert_select "span.text-amber-700", text: "Time:"

    # Flipped Table Structure: columns for days (th), rows for meals (tr/th)
    assert_select "table"
    assert_select "th", text: /Mon/i
    assert_select "th", text: /Thu/i
    assert_select "th", text: /Breakfast/i
    assert_select "th", text: /Lunch/i
    assert_select "th", text: /Dinner/i

    # Centered week title and no top-left household/clutter
    assert_not_includes response.body, "Weekly Refrigerator Menu"
    assert_not_includes response.body, "FamilyPlates Balanced Schedule"

    # No meal icons on weekly printout
    assert_not_includes response.body, "☀️ Breakfast"
    assert_not_includes response.body, "🥪 Lunch"
    assert_not_includes response.body, "🍽️ Dinner"

    # No footer on calendar printout
    assert_not_includes response.body, "Cut here"
    assert_not_includes response.body, "✂️"

    # Rounded corners matching outside border
    assert_select ".rounded-2xl.overflow-hidden"
  end

  test "should get print month view with centered month title, no family name/top-left clutter, and spelled out meal types" do
    test_date = @meal_plan.week_start_date + 4.days
    member = family_members(:one)
    recipe = recipes(:one)
    @meal_plan.meal_plan_slots.create!(date: test_date, meal_type: "breakfast", custom_title: "Blueberry Oatmeal with Toasted Almonds", family_member: member)
    @meal_plan.meal_plan_slots.create!(date: test_date, meal_type: "lunch", custom_title: "Turkey Sandwich on Sourdough", family_member: member)
    @meal_plan.meal_plan_slots.create!(date: test_date, meal_type: "dinner", recipe: recipe, family_member: member)

    get print_meal_plan_url(@meal_plan, view: "month")
    assert_response :success
    assert_includes response.body, "Blueberry Oatmeal with Toasted Almonds"
    assert_includes response.body, "Turkey Sandwich on Sourdough"
    assert_includes response.body, recipe.title
    assert_includes response.body, member.name
    # Cook: and Time: in distinct colors identical to weekly view
    assert_select "span.text-blue-700", text: "Cook:"
    assert_select "span.text-amber-700", text: "Time:"

    # Meal types must be spelled out (Breakfast, Lunch, Dinner), centered headers
    assert_includes response.body, "Breakfast"
    assert_includes response.body, "Lunch"
    assert_includes response.body, "Dinner"
    assert_not_includes response.body, "text-amber-900"
    assert_not_includes response.body, "text-teal-900"
    # Light grey horizontal bar divider below breakfast and lunch entries (uncollapsible hr)
    assert_select "hr.border-slate-300"

    # Top-left info and household name should be omitted to maximize space
    assert_not_includes response.body, "Monthly Kitchen Menu & Family Schedule"
    assert_not_includes response.body, "Monthly kitchen menu"
    assert_not_includes response.body, "FamilyPlates Balanced Schedule"
  end
end
