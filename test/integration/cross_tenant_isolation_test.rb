require "test_helper"

# The invariant this suite exists to hold: a session belonging to one household
# must never reach another household's records, whatever ID it presents.
#
# It is written as a sweep rather than a handful of examples because the failure
# mode is a single controller that forgets to scope its finder. One route added
# next year with `Recipe.find(params[:id])` instead of
# `current_household.recipes.find(params[:id])` is exactly the mistake this is
# here to catch, and a fixed list of examples would not catch it.
#
# Phase 0 of docs/ideas/household-identity-and-tenancy.md. The app is
# single-tenant today, so nothing here is presently exploitable - the second
# household cannot even be created through the UI. That is the point: these
# assertions have to be true *before* a second household is possible, because
# afterwards every one of them is a cross-tenant takeover.
class CrossTenantIsolationTest < ActionDispatch::IntegrationTest
  setup do
    @intruder = family_members(:one)             # organizer of household one
    @other = households(:two)

    # Built here rather than in fixtures so the 324 tests that count rows in the
    # primary household are untouched by this file.
    @other_member = @other.family_members.create!(
      name: "Miller Mum", role: "admin", pin: "4321",
      avatar_color: "#10B981", avatar_icon: "star"
    )
    @other_recipe = @other.recipes.create!(
      title: "Miller Casserole", instructions: "Bake it.", number: 99
    )
    @other_meal_plan = meal_plans(:two)
    @other_meal_plan.update_column(:number, 99)
    @other_pantry_item = @other.pantry_items.create!(
      name: "Miller Flour", aisle_category: "Pantry & Grains"
    )
    # A PIN-less profile in the other household. This is the cheapest possible
    # target: no credential stands between a stranger and it except scoping.
    @other_child = @other.family_members.create!(
      name: "Miller Kid", role: "member",
      avatar_color: "#84CC16", avatar_icon: "smile"
    )

    sign_in_as(@intruder)
    assert_equal households(:one), @intruder.household,
      "precondition: the intruder must not already be in the household under attack"
  end

  # Reading another household's records.
  test "a signed-in organizer cannot read another household's recipe" do
    get recipe_url(@other_recipe)
    assert_response :not_found
  end

  test "a signed-in organizer cannot read another household's meal plan" do
    get meal_plan_url(@other_meal_plan)
    assert_response :not_found
  end

  test "a signed-in organizer cannot print another household's meal plan" do
    get print_meal_plan_url(@other_meal_plan)
    assert_response :not_found
  end

  test "a signed-in organizer cannot read another household's grocery list" do
    get plan_grocery_list_url(@other_meal_plan)
    assert_response :not_found
  end

  # Writing to another household's records.
  test "a signed-in organizer cannot edit another household's recipe" do
    patch recipe_url(@other_recipe), params: { recipe: { title: "Owned" } }
    assert_response :not_found
    assert_equal "Miller Casserole", @other_recipe.reload.title
  end

  test "a signed-in organizer cannot destroy another household's recipe" do
    assert_no_difference "Recipe.count" do
      delete recipe_url(@other_recipe)
    end
    assert_response :not_found
  end

  test "a signed-in organizer cannot toggle another household's pantry staple" do
    was = @other_pantry_item.is_staple
    patch toggle_staple_pantry_item_url(@other_pantry_item)
    assert_response :not_found
    assert_equal was, @other_pantry_item.reload.is_staple
  end

  test "a signed-in organizer cannot destroy another household's pantry item" do
    assert_no_difference "PantryItem.count" do
      delete pantry_item_url(@other_pantry_item)
    end
    assert_response :not_found
  end

  test "a signed-in organizer cannot add a slot to another household's meal plan" do
    assert_no_difference "MealPlanSlot.count" do
      post meal_plan_meal_plan_slots_url(@other_meal_plan), params: {
        meal_plan_slot: { date: Date.current, meal_type: "dinner" }
      }
    end
    assert_response :not_found
  end

  # The admin surface, which is where the roster and the household itself live.
  test "a signed-in organizer cannot edit another household's roster member" do
    patch admin_family_member_url(@other_member), params: {
      family_member: { name: "Renamed" }
    }
    assert_response :not_found
    assert_equal "Miller Mum", @other_member.reload.name
  end

  test "a signed-in organizer cannot reset another household's PIN" do
    patch reset_pin_admin_family_member_url(@other_member), params: {
      family_member: { pin: "0000" }
    }
    assert_response :not_found
    assert @other_member.reload.verify_pin("4321"), "the other household's PIN must be unchanged"
  end

  test "a signed-in organizer cannot destroy another household's roster member" do
    assert_no_difference "FamilyMember.count" do
      delete admin_family_member_url(@other_member)
    end
    assert_response :not_found
  end

  # Bulk endpoints take a list of IDs rather than a single :id, so they bypass
  # the set_* finders entirely and need scoping of their own.
  test "bulk destroy ignores another household's recipe ids" do
    assert_no_difference "Recipe.count" do
      post bulk_destroy_recipes_url, params: { recipe_ids: [ @other_recipe.id ] }
    end
    assert Recipe.exists?(@other_recipe.id), "the other household's recipe must survive"
  end

  test "bulk update ignores another household's recipe ids" do
    post bulk_update_recipes_url, params: {
      recipe_ids: [ @other_recipe.id ], bulk_action: "add_tag", tag: "Owned"
    }
    assert_not_includes @other_recipe.reload.tags.to_s, "Owned"
  end

  # The front door. /select_profile and /set_profile are open by design on an
  # appliance install - the operator has not opted into REQUIRE_LOGIN - so the
  # only thing standing between a stranger and a profile is which household the
  # picker is willing to look in.
  test "an anonymous visitor cannot take a PIN-less profile in another household" do
    sign_out

    post set_profile_url(@other_child)
    assert_response :not_found
    assert_nil active_family_member_id, "no session may be issued for another household"
  end

  test "an anonymous visitor cannot take an admin profile in another household even with its PIN" do
    sign_out

    post set_profile_url(@other_member), params: { pin: "4321" }
    assert_response :not_found
    assert_nil active_family_member_id, "a correct PIN must not help across households"
  end

  test "a signed-in member cannot switch into another household's profile" do
    post set_profile_url(@other_child)
    assert_response :not_found
    assert signed_in_as?(@intruder), "the original session must be untouched"
  end

  test "the picker does not list another household's profiles" do
    sign_out

    get select_profile_url
    assert_response :success
    assert_no_match(/Miller Kid/, response.body)
    assert_no_match(/Miller Mum/, response.body)
  end

  # Listings must not leak the other household's rows, which no :id-based test
  # would catch.
  test "the recipe index does not list another household's recipes" do
    get recipes_url
    assert_response :success
    assert_no_match(/Miller Casserole/, response.body)
  end

  test "the roster does not list another household's members" do
    get family_members_url
    assert_response :success
    assert_no_match(/Miller Mum/, response.body)
  end

  test "the admin roster does not list another household's members" do
    get admin_family_members_url
    assert_response :success
    assert_no_match(/Miller Mum/, response.body)
  end
end
