require "test_helper"

class GroceryListsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = family_members(:one)
    @member = family_members(:two)
    @meal_plan = meal_plans(:one)
    sign_in_as(@admin)
  end

  def week_params(monday)
    { from: monday.iso8601, to: (monday + 6.days).iso8601 }
  end

  def this_monday = households(:one).today.beginning_of_week

  test "each checklist box is named by its item" do
    get grocery_list_url

    boxes = css_select("input[type=checkbox][data-checklist-target=checkbox]")
    assert boxes.any?, "precondition: the fixture plan puts items on the list"
    boxes.each do |box|
      assert_select "##{box['aria-labelledby']}", 1
    end
  end

  test "checklist item ids are unique and do not depend on list position" do
    get grocery_list_url

    ids = css_select("input[type=checkbox][data-checklist-target=checkbox]").map { |box| box["value"] }
    assert_equal ids.uniq, ids
    ids.each { |id| assert_no_match(/_\d+_/, id) }
  end

  test "should get current grocery list" do
    get grocery_list_url
    assert_response :success
  end

  test "admin sees active checkboxes and reset button" do
    get grocery_list_url
    assert_response :success
    assert_select "button", text: "Reset"
  end

  test "non-admin member sees disabled checkboxes and no reset button" do
    sign_in_as(@member)
    get grocery_list_url
    assert_response :success
    assert_select "button", text: "Reset", count: 0
    assert_select "span", text: "Read-Only"
  end

  # @card-62.1
  test "with no dates the list covers the current week" do
    get grocery_list_url

    assert_select "[data-checklist-from-value=?]", this_monday.iso8601
    assert_select "[data-checklist-to-value=?]", (this_monday + 6.days).iso8601
    assert_select "[data-testid=grocery-range-label]", text: GroceryRange.default(households(:one).today).label
  end

  # @card-62.1
  test "an explicit range lists the meals planned in it" do
    next_monday = this_monday + 7.days
    plan = households(:one).current_meal_plan(next_monday)
    recipe = households(:one).recipes.create!(title: "Next Week Stew", instructions: "Stew.")
    recipe.recipe_ingredients.create!(name: "Parsnips", quantity: 3, unit: "pcs", aisle_category: "Produce")
    plan.meal_plan_slots.create!(date: next_monday, meal_type: "dinner", recipe: recipe)

    get grocery_list_url(week_params(next_monday))
    assert_select "span.item-label", text: /Parsnips/
    assert_select "[data-checklist-from-value=?]", next_monday.iso8601

    get grocery_list_url
    assert_select "span.item-label", text: /Parsnips/, count: 0
  end

  # @card-62.1
  test "an unreadable or reversed range falls back to the current week" do
    [ { from: "nonsense", to: "2026-10-25" },
      { from: "2026-10-25" },
      { from: "2026-10-25", to: "2026-10-19" } ].each do |bad|
      get grocery_list_url(bad)
      assert_response :success
      assert_select "[data-checklist-from-value=?]", this_monday.iso8601
      assert_select "[data-testid=grocery-range-clamped]", count: 0
    end
  end

  # @card-62.1
  test "a range longer than 42 days is cut to 42 days and says so" do
    get grocery_list_url(from: "2026-10-01", to: "2027-03-01")

    assert_select "[data-checklist-from-value=?]", "2026-10-01"
    assert_select "[data-checklist-to-value=?]", "2026-11-11"
    assert_select "[data-testid=grocery-range-clamped]", text: /at most 42 days/

    get grocery_list_url(from: "2026-10-01", to: "2026-11-11")
    assert_select "[data-testid=grocery-range-clamped]", count: 0
  end

  # @card-62.5
  test "the old per-plan address redirects to that plan's week" do
    get plan_grocery_list_url(@meal_plan)
    assert_redirected_to grocery_list_path(week_params(@meal_plan.week_start_date))

    get plan_grocery_list_url(@meal_plan.id)
    assert_redirected_to grocery_list_path(week_params(@meal_plan.week_start_date))

    get plan_grocery_list_url("current")
    assert_redirected_to grocery_list_path
  end

  # @card-62.5
  # @card-62.6
  test "another household's plan is not found on the old address" do
    get plan_grocery_list_url(meal_plans(:two).id)
    assert_response :not_found
  end

  # @card-62.2
  test "presets render as links and the active one is marked" do
    today = households(:one).today
    get grocery_list_url

    [ "This week", "Next week", "From today", "This month", "Next month" ].each do |name|
      assert_select "[role=group][aria-label='Shopping period'] a", text: name
    end
    assert_select "[role=group][aria-label='Shopping period'] a[aria-current=true]", count: 1, text: "This week"

    month = GroceryRange.new(today.beginning_of_month, today.end_of_month, today: today)
    get grocery_list_url(month.params)
    assert_select "[role=group][aria-label='Shopping period'] a[aria-current=true]", count: 1, text: "This month"

    get grocery_list_url(from: "2026-01-02", to: "2026-01-05")
    assert_select "[role=group][aria-label='Shopping period'] a[aria-current=true]", count: 0
    assert_select "input[type=date][name=from][value='2026-01-02']"
    assert_select "input[type=date][name=to][value='2026-01-05']"
  end

  # @card-62.2
  test "arrows step a whole month for a calendar month, otherwise the range's length" do
    get grocery_list_url(from: "2026-11-01", to: "2026-11-30")
    assert_select "a[aria-label='Previous month'][href=?]", grocery_list_path(from: "2026-10-01", to: "2026-10-31")
    assert_select "a[aria-label='Next month'][href=?]", grocery_list_path(from: "2026-12-01", to: "2026-12-31")

    get grocery_list_url(from: "2026-10-19", to: "2026-10-23")
    assert_select "a[aria-label='Previous period'][href=?]", grocery_list_path(from: "2026-10-14", to: "2026-10-18")
    assert_select "a[aria-label='Next period'][href=?]", grocery_list_path(from: "2026-10-24", to: "2026-10-28")
  end

  # @card-62.4
  test "the Planner link opens the week containing the range start" do
    get grocery_list_url(from: "2026-10-21", to: "2026-10-30")
    assert_select "a[href=?]", meal_plans_path(week: "2026-10-21"), text: /Planner/
  end

  # @card-62.1
  test "a range with no meals says so and points at the planner" do
    get grocery_list_url(from: "2031-03-03", to: "2031-03-09")

    assert_select "h3", text: "No meals planned between Mar 3 and Mar 9, 2031"
    assert_select "a[href=?]", meal_plans_path(week: "2031-03-03")
  end

  # @card-62.4
  test "the planner offers a grocery list link for its week and its month" do
    plan = @meal_plan
    get meal_plan_url(plan)
    assert_select "a[href=?]", grocery_list_path(week_params(plan.week_start_date)), text: /Grocery list/

    month = plan.week_start_date.beginning_of_month
    get meal_plan_url(plan, view: "month", month: month)
    assert_select "a[href=?]", grocery_list_path(from: month.iso8601, to: month.end_of_month.iso8601), text: /Grocery list/
  end
end
