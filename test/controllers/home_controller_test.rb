require "test_helper"

# The root route is the one URL every visitor hits, and it is the only action
# marked allow_unauthenticated_access outside the wizard and the profile picker.
# All three of its branches are redirects, so nothing else in the suite notices
# if one of them starts sending people to the wrong place.
class HomeControllerTest < ActionDispatch::IntegrationTest
  test "a fresh install sends the first visitor into onboarding" do
    Household.destroy_all

    get root_url

    assert_redirected_to onboarding_url
  end

  test "a configured install sends an anonymous visitor to the profile picker" do
    assert Household.exists?, "precondition: this install is configured"

    get root_url

    assert_redirected_to select_profile_url
  end

  test "a signed-in member lands on their household's current meal plan" do
    member = family_members(:one)
    sign_in_as(member)

    get root_url

    plan = member.household.current_meal_plan
    assert_redirected_to meal_plan_url(plan)
    assert_equal member.household_id, plan.household_id, "the plan must belong to the visitor's household"
  end

  test "the meal plan the root route lands on is followable" do
    sign_in_as(family_members(:one))

    get root_url
    follow_redirect!

    assert_response :success
  end

  test "root does not leak another household's plan" do
    other = Household.create!(name: "Neighbours", breakfast_time: "07:00", lunch_time: "12:00", dinner_time: "18:00")
    other.meal_plans.create!(week_start_date: Date.current.beginning_of_week)

    sign_in_as(family_members(:one))
    get root_url
    plan_id = response.location[%r{/meal_plans/(\d+)}, 1].to_i

    assert_equal households(:one).id, MealPlan.find(plan_id).household_id
  end
end
