require "test_helper"

class MealPlanTest < ActiveSupport::TestCase
  test "validates uniqueness of week_start_date per household" do
    duplicate = MealPlan.new(household: households(:one), week_start_date: meal_plans(:one).week_start_date)
    assert_not duplicate.valid?
  end

  test "returns 7 days" do
    plan = meal_plans(:one)
    assert_equal 7, plan.days.count
    assert_equal plan.week_start_date, plan.days.first
    assert_equal plan.week_start_date + 6.days, plan.days.last
  end

  test "slot_for returns correct slot" do
    plan = meal_plans(:one)
    slot = plan.slot_for(Date.current.beginning_of_week, "dinner")
    assert_not_nil slot
    assert_equal recipes(:one), slot.recipe
  end

  test "available_leftovers_for considers breakfast, lunch, and dinner leftovers" do
    plan = meal_plans(:one)
    household = plan.household
    MealPlanSlot.delete_all

    pancake_bake = household.recipes.create!(title: "Pancake Bake", yields_leftovers: true, meal_types: "breakfast")
    salad = household.recipes.create!(title: "Caesar Salad", yields_leftovers: false, meal_types: "lunch")
    chili = household.recipes.create!(title: "Beef Chili", yields_leftovers: true, meal_types: "dinner")

    # Day 1: Monday Breakfast (Pancake Bake) & Monday Dinner (Chili)
    monday = plan.week_start_date
    plan.meal_plan_slots.create!(date: monday, meal_type: "breakfast", recipe: pancake_bake, is_leftover: false)
    plan.meal_plan_slots.create!(date: monday, meal_type: "dinner", recipe: chili, is_leftover: false)

    # Check available leftovers for Monday Lunch (should see breakfast Pancake Bake)
    lunch_leftovers = plan.available_leftovers_for(monday, "lunch")
    assert_equal 1, lunch_leftovers.count
    assert_equal pancake_bake, lunch_leftovers.first[:recipe]

    # Check available leftovers for Tuesday Breakfast (should see Chili and Pancake Bake, prioritized by yields_leftovers)
    tuesday = monday + 1.day
    tuesday_b_leftovers = plan.available_leftovers_for(tuesday, "breakfast")
    recipe_ids = tuesday_b_leftovers.map { |l| l[:recipe].id }
    assert_includes recipe_ids, pancake_bake.id
    assert_includes recipe_ids, chili.id
  end

  test "available_leftovers_for rolls across week boundaries for 3 days" do
    household = households(:one)
    MealPlanSlot.delete_all

    week1 = household.meal_plans.find_or_create_by!(week_start_date: Date.new(2026, 8, 17)) # Monday Aug 17
    week2 = household.meal_plans.find_or_create_by!(week_start_date: Date.new(2026, 8, 24)) # Monday Aug 24

    sunday_roast = household.recipes.create!(title: "Sunday Roast Beef", yields_leftovers: true)
    saturday_soup = household.recipes.create!(title: "Saturday Minestrone", yields_leftovers: false)

    # Week 1 meals on Saturday and Sunday
    week1.meal_plan_slots.create!(date: Date.new(2026, 8, 22), meal_type: "lunch", recipe: saturday_soup, is_leftover: false) # Sat Aug 22
    week1.meal_plan_slots.create!(date: Date.new(2026, 8, 23), meal_type: "dinner", recipe: sunday_roast, is_leftover: false) # Sun Aug 23

    # On Week 2 Monday Aug 24 Lunch: both Saturday soup (2 days ago) and Sunday roast (1 day ago) should be available
    monday_leftovers = week2.available_leftovers_for(Date.new(2026, 8, 24), "lunch")
    monday_recipe_ids = monday_leftovers.map { |l| l[:recipe].id }
    assert_includes monday_recipe_ids, sunday_roast.id
    assert_includes monday_recipe_ids, saturday_soup.id

    # On Week 2 Wednesday Aug 26 Lunch (3 days after Sunday roast): Sunday roast is still available, Saturday soup (4 days ago) has expired
    wednesday_leftovers = week2.available_leftovers_for(Date.new(2026, 8, 26), "lunch")
    wednesday_recipe_ids = wednesday_leftovers.map { |l| l[:recipe].id }
    assert_includes wednesday_recipe_ids, sunday_roast.id
    assert_not_includes wednesday_recipe_ids, saturday_soup.id
  end

  test "week_label formats single-month and multi-month spans cleanly without wrapping" do
    single_month_plan = MealPlan.new(week_start_date: Date.new(2026, 8, 17))
    assert_equal "August 17 – 23, 2026", single_month_plan.week_label

    multi_month_plan = MealPlan.new(week_start_date: Date.new(2026, 8, 31))
    assert_equal "Aug 31 – Sep 6, 2026", multi_month_plan.week_label
  end

  test "available_leftovers_for supports multiple simultaneous leftover options from breakfast and dinner" do
    household = households(:one)
    MealPlanSlot.delete_all

    plan = household.meal_plans.find_or_create_by!(week_start_date: Date.new(2026, 8, 17))
    monday = Date.new(2026, 8, 17)

    quiche = household.recipes.create!(title: "Spinach Quiche", yields_leftovers: true)
    pot_roast = household.recipes.create!(title: "Beef Pot Roast", yields_leftovers: true)
    salad = household.recipes.create!(title: "Tossed Salad", yields_leftovers: false)

    plan.meal_plan_slots.create!(date: monday, meal_type: "breakfast", recipe: quiche, is_leftover: false)
    plan.meal_plan_slots.create!(date: monday, meal_type: "dinner", recipe: pot_roast, is_leftover: false)

    # Next day Tuesday Lunch: both Monday breakfast Quiche and Monday dinner Pot Roast should be available leftover candidates
    tuesday = monday + 1.day
    leftovers = plan.available_leftovers_for(tuesday, "lunch")
    
    assert_equal 2, leftovers.count
    leftover_titles = leftovers.map { |l| l[:recipe].title }
    assert_includes leftover_titles, "Spinach Quiche"
    assert_includes leftover_titles, "Beef Pot Roast"
  end
end
