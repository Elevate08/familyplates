require "test_helper"

class RecipeRequestTest < ActiveSupport::TestCase
  setup do
    @recipe = recipes(:one)
    @family_member = family_members(:one)
    @household = households(:one)
    @meal_plan = meal_plans(:one)

    # Clean state for isolated lifecycle tests
    RecipeRequest.delete_all
    MealPlanSlot.delete_all
  end

  test "creates active craving request by default" do
    # Clear fixtures for clean test
    RecipeRequest.delete_all

    request = RecipeRequest.create!(
      recipe: @recipe,
      family_member: @family_member,
      week_start_date: Date.current.beginning_of_week
    )

    assert_nil request.fulfilled_at
    assert_includes RecipeRequest.active, request
    assert @recipe.requested_by?(@family_member)
    assert_equal 1, @recipe.request_count_for_week
    assert_includes @recipe.requesters_for_week, @family_member
  end

  test "prevents duplicate active request by the same member for the same recipe" do
    RecipeRequest.delete_all

    RecipeRequest.create!(
      recipe: @recipe,
      family_member: @family_member,
      week_start_date: Date.current.beginning_of_week
    )

    duplicate = RecipeRequest.new(
      recipe: @recipe,
      family_member: @family_member,
      week_start_date: Date.current.beginning_of_week
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:recipe_id], "has already been requested and is currently active"
  end

  test "remains active when scheduled on future meal plan slot" do
    RecipeRequest.delete_all

    request = RecipeRequest.create!(
      recipe: @recipe,
      family_member: @family_member,
      week_start_date: Date.current.beginning_of_week
    )

    # Schedule for 3 days in the future
    @meal_plan.meal_plan_slots.create!(
      recipe: @recipe,
      date: Date.current + 3.days,
      meal_type: "dinner"
    )

    RecipeRequest.auto_fulfill_passed_slots!
    assert_nil request.reload.fulfilled_at
    assert @recipe.requested_by?(@family_member)
  end

  test "auto fulfills request when scheduled date is in the past or today" do
    RecipeRequest.delete_all

    request = RecipeRequest.create!(
      recipe: @recipe,
      family_member: @family_member,
      week_start_date: Date.current.beginning_of_week,
      created_at: 2.days.ago
    )

    # Schedule for yesterday (meaning the meal was cooked/passed)
    @meal_plan.meal_plan_slots.create!(
      recipe: @recipe,
      date: Date.current - 1.day,
      meal_type: "dinner"
    )

    assert_not_nil request.reload.fulfilled_at
    assert_not @recipe.requested_by?(@family_member)
    assert_equal 0, @recipe.request_count_for_week
  end

  test "auto_fulfill_passed_slots! fulfills active requests whose plan date has passed" do
    RecipeRequest.delete_all

    request = RecipeRequest.create!(
      recipe: @recipe,
      family_member: @family_member,
      week_start_date: Date.current.beginning_of_week,
      created_at: 3.days.ago
    )

    # Insert slot without triggering callbacks
    slot = @meal_plan.meal_plan_slots.build(
      recipe: @recipe,
      date: Date.current - 1.day,
      meal_type: "dinner"
    )
    slot.save!(validate: false)

    # Run batch fulfillment
    RecipeRequest.auto_fulfill_passed_slots!

    assert_not_nil request.reload.fulfilled_at
    assert_not_includes RecipeRequest.active, request
  end

  test "allows re-requesting a recipe in the future after prior request was fulfilled" do
    RecipeRequest.delete_all

    # Old fulfilled request from last month
    RecipeRequest.create!(
      recipe: @recipe,
      family_member: @family_member,
      week_start_date: 1.month.ago.to_date.beginning_of_week,
      fulfilled_at: 1.month.ago
    )

    # New active request today
    new_request = RecipeRequest.create!(
      recipe: @recipe,
      family_member: @family_member,
      week_start_date: Date.current.beginning_of_week
    )

    assert_nil new_request.fulfilled_at
    assert @recipe.requested_by?(@family_member)
    assert_equal 1, @recipe.request_count_for_week
  end

  test "scheduling a requested recipe for today immediately fulfills the request" do
    RecipeRequest.delete_all

    request = RecipeRequest.create!(
      recipe: @recipe,
      family_member: @family_member,
      week_start_date: Date.current.beginning_of_week
    )

    assert_nil request.fulfilled_at
    assert @recipe.requested_by?(@family_member)

    # Schedule for today
    @meal_plan.meal_plan_slots.create!(
      recipe: @recipe,
      date: Date.current,
      meal_type: "dinner"
    )

    assert_not_nil request.reload.fulfilled_at
    assert_not @recipe.requested_by?(@family_member)
    assert_equal 0, @recipe.request_count_for_week
  end

  test "persists active request across multiple calendar weeks if unscheduled" do
    RecipeRequest.delete_all

    # Request made two weeks ago
    request = RecipeRequest.create!(
      recipe: @recipe,
      family_member: @family_member,
      week_start_date: 2.weeks.ago.to_date.beginning_of_week,
      created_at: 2.weeks.ago
    )

    # Never scheduled in any meal plan slot
    RecipeRequest.auto_fulfill_passed_slots!

    assert_nil request.reload.fulfilled_at
    assert @recipe.requested_by?(@family_member)
    assert_equal 1, @recipe.request_count_for_week
  end
end
