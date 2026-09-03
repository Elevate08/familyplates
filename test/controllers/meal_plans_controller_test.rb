require "test_helper"

class MealPlansControllerTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @admin = family_members(:one)
    @meal_plan = meal_plans(:one)
    sign_in_as(@admin)
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
    # Anchored on a week that straddles a month boundary (Aug 31 - Sep 6, 2026)
    # so this covers the print-out of a majority-month week, not just the easy
    # case of a week sitting wholly inside one month.
    plan = boundary_meal_plan
    test_date = plan.week_start_date + 4.days
    member = family_members(:one)
    recipe = recipes(:one)
    plan.meal_plan_slots.create!(date: test_date, meal_type: "breakfast", custom_title: "Blueberry Oatmeal with Toasted Almonds", family_member: member)
    plan.meal_plan_slots.create!(date: test_date, meal_type: "lunch", custom_title: "Turkey Sandwich on Sourdough", family_member: member)
    plan.meal_plan_slots.create!(date: test_date, meal_type: "dinner", recipe: recipe, family_member: member)

    get print_meal_plan_url(plan, view: "month")
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

  test "should sync calendar when enabled" do
    @household.update!(google_calendar_enabled: true, google_calendar_id: "family@group.calendar.google.com")

    post sync_calendar_meal_plan_url(@meal_plan)
    assert_redirected_to meal_plan_url(@meal_plan)
    assert_equal "Weekly meal plan synced to Google Calendar! 📅", flash[:notice]
  end

  test "should alert when syncing calendar but not enabled" do
    @household.update!(google_calendar_enabled: false)

    post sync_calendar_meal_plan_url(@meal_plan)
    assert_redirected_to meal_plan_url(@meal_plan)
    assert_equal "Google Calendar sync is not configured yet. Set it up in the Admin Control Center.", flash[:alert]
  end

  # --- Default month selection for weeks that straddle a month boundary -------
  #
  # A week belongs to whichever month holds most of its seven days. Anchoring on
  # the week's first day instead drops the tail of the current week out of the
  # calendar for the several days a year a week starts near a month's end.

  test "month view defaults to the month holding most of the week when the week ends in the next month" do
    # Aug 31 - Sep 6, 2026: one day in August, six in September.
    plan = boundary_meal_plan
    plan.meal_plan_slots.create!(date: Date.new(2026, 9, 4), meal_type: "dinner", custom_title: "Friday Fish Tacos")

    get meal_plan_url(plan, view: "month")

    assert_response :success
    assert_includes response.body, "September 2026"
    assert_includes response.body, "Friday Fish Tacos"
  end

  test "month view defaults to the month holding most of the week when the week starts in the previous month" do
    # Apr 27 - May 3, 2026: four days in April, three in May.
    plan = @household.meal_plans.find_or_create_by!(week_start_date: Date.new(2026, 4, 27))
    plan.meal_plan_slots.create!(date: Date.new(2026, 4, 28), meal_type: "dinner", custom_title: "Tuesday Ratatouille")
    plan.meal_plan_slots.create!(date: Date.new(2026, 5, 1), meal_type: "dinner", custom_title: "Friday Paella")

    get meal_plan_url(plan, view: "month")

    assert_response :success
    assert_includes response.body, "April 2026"
    assert_includes response.body, "Tuesday Ratatouille"
    assert_not_includes response.body, "Friday Paella"
  end

  test "month view honours an explicit month over the week's majority month" do
    plan = boundary_meal_plan
    plan.meal_plan_slots.create!(date: Date.new(2026, 9, 4), meal_type: "dinner", custom_title: "Friday Fish Tacos")

    get meal_plan_url(plan, view: "month", month: "2026-08-01")

    assert_response :success
    assert_includes response.body, "August 2026"
    assert_not_includes response.body, "Friday Fish Tacos"
  end

  test "print month view uses the same default month as the planner" do
    plan = boundary_meal_plan

    get meal_plan_url(plan, view: "month")
    assert_includes response.body, "September 2026"

    get print_meal_plan_url(plan, view: "month")
    assert_includes response.body, "September 2026"
  end

  private

  # A plan whose week straddles a month boundary, with the majority of its days
  # in the second month. find_or_create_by! because this is the current week
  # whenever the suite happens to run during it.
  def boundary_meal_plan
    @household.meal_plans.find_or_create_by!(week_start_date: Date.new(2026, 8, 31))
  end
end
