require "test_helper"

# Characterization for auto_fulfill_passed_slots!, written against the existing
# per-record implementation so the batched rewrite has something to be measured
# against. Every case here describes what the old loop already did.
class RecipeRequestAutoFulfillTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
    @member = family_members(:one)
    @plan = @household.current_meal_plan
    RecipeRequest.delete_all
    MealPlanSlot.delete_all
  end

  def request_for(recipe, week_start: @plan.week_start_date, created_at: nil)
    req = RecipeRequest.create!(recipe: recipe, family_member: @member, week_start_date: week_start)
    req.update_columns(created_at: created_at) if created_at
    req
  end

  def slot_on(date, recipe)
    plan = @household.meal_plans.find_or_create_by!(week_start_date: date.beginning_of_week)
    plan.meal_plan_slots.find_or_initialize_by(date: date, meal_type: "dinner").tap { |s| s.update!(recipe: recipe) }
  end

  test "fulfils a request whose slot date has arrived" do
    req = request_for(recipes(:one))
    slot_on(Date.current, recipes(:one))

    RecipeRequest.auto_fulfill_passed_slots!

    assert_not_nil req.reload.fulfilled_at
    assert_equal Date.current, req.fulfilled_at.to_date
  end

  test "leaves a request whose slot is still in the future" do
    req = request_for(recipes(:one))
    slot_on(Date.current + 3, recipes(:one))

    RecipeRequest.auto_fulfill_passed_slots!

    assert_nil req.reload.fulfilled_at
  end

  test "ignores a slot that predates the request" do
    req = request_for(recipes(:one), week_start: Date.current.beginning_of_week, created_at: 2.days.ago)
    slot_on(Date.current - 30, recipes(:one))

    RecipeRequest.auto_fulfill_passed_slots!

    assert_nil req.reload.fulfilled_at, "a slot before the request's floor must not fulfil it"
  end

  test "the floor is the earlier of week_start_date and created_at" do
    # created_at is older than week_start_date, so the floor is created_at and a
    # slot between the two counts.
    req = request_for(recipes(:one), week_start: Date.current.beginning_of_week, created_at: 10.days.ago)
    slot_on(Date.current - 5, recipes(:one))

    RecipeRequest.auto_fulfill_passed_slots!

    assert_not_nil req.reload.fulfilled_at
    assert_equal (Date.current - 5), req.fulfilled_at.to_date
  end

  test "fulfils with the earliest qualifying slot, not the latest" do
    req = request_for(recipes(:one), created_at: 10.days.ago)
    slot_on(Date.current - 4, recipes(:one))
    slot_on(Date.current - 1, recipes(:one))

    RecipeRequest.auto_fulfill_passed_slots!

    assert_equal (Date.current - 4), req.reload.fulfilled_at.to_date
  end

  test "leaves an already fulfilled request untouched" do
    req = request_for(recipes(:one))
    slot_on(Date.current, recipes(:one))
    original = 3.days.ago.change(usec: 0)
    req.update_columns(fulfilled_at: original)

    RecipeRequest.auto_fulfill_passed_slots!

    assert_equal original.to_i, req.reload.fulfilled_at.to_i
  end

  test "a request for a recipe with no slots stays open" do
    req = request_for(recipes(:two))
    slot_on(Date.current, recipes(:one))

    RecipeRequest.auto_fulfill_passed_slots!

    assert_nil req.reload.fulfilled_at
  end

  test "does not touch another household's requests" do
    other = households(:two)
    other_member = other.family_members.create!(name: "Neighbour", role: "member", avatar_color: "#10B981")
    other_recipe = other.recipes.create!(title: "Not Ours", instructions: "x")
    other_plan = other.meal_plans.find_or_create_by!(week_start_date: Date.current.beginning_of_week)
    other_plan.meal_plan_slots.create!(date: Date.current, meal_type: "dinner", recipe: other_recipe)
    other_request = RecipeRequest.create!(recipe: other_recipe, family_member: other_member,
                                          week_start_date: Date.current.beginning_of_week)

    RecipeRequest.auto_fulfill_passed_slots!(@household)

    assert_nil other_request.reload.fulfilled_at,
      "scoping to a household must not reach across into another one"
  end

  test "the query count does not grow with the number of requests" do
    requests = 12.times.map do |i|
      recipe = @household.recipes.create!(title: "Batch Recipe #{i}", instructions: "x")
      member = @household.family_members.create!(name: "Eater #{i}", role: "member", avatar_color: "#10B981")
      # An old floor, so all twelve slot dates below qualify regardless of which
      # weekday the suite runs on. Dating them within the current week would make
      # the earliest ones fall before the request's floor and legitimately not
      # fulfil - which is correct behaviour, and would make this a test of the
      # floor rather than of the query count.
      req = RecipeRequest.create!(recipe: recipe, family_member: member,
                                  week_start_date: (Date.current - 40).beginning_of_week)
      # A distinct date per recipe: one slot per (plan, date, meal_type), so
      # reusing today for all twelve would leave a single slot pointing at the
      # last recipe.
      slot_on(Date.current - i, recipe)
      req
    end

    # MealPlanSlot's after_save already fulfils these on creation, so reopen them
    # - otherwise the method under test has nothing to do and any query budget
    # passes.
    RecipeRequest.where(id: requests.map(&:id)).update_all(fulfilled_at: nil)
    assert_equal 12, RecipeRequest.active.count, "precondition: twelve requests to resolve"

    queries = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      queries += 1 unless payload[:name].to_s =~ /SCHEMA|TRANSACTION/
    end
    RecipeRequest.auto_fulfill_passed_slots!(@household)
    ActiveSupport::Notifications.unsubscribe(sub)

    assert_equal 12, RecipeRequest.where.not(fulfilled_at: nil).count,
      "all twelve should have been fulfilled - otherwise the budget below is meaningless"

    # Two reads plus one write per fulfilled request. The old loop added a slot
    # query per request on top of that, so it could not come in under this.
    assert_operator queries, :<=, 12 + 4,
      "#{queries} queries for 12 requests - this should not scale per request"
  end
end
