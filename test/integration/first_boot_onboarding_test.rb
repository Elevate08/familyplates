require "test_helper"

class FirstBootOnboardingTest < ActionDispatch::IntegrationTest
  # The five hand-rolled `Household.none?` checks this replaced each guarded one
  # controller, and three of them sat in controllers that skip
  # require_authentication - so a sixth controller added with
  # allow_unauthenticated_access and no inline check would simply have been
  # unguarded. require_installation runs regardless, and this asserts it across
  # the paths a stranger can actually reach on a fresh install.
  test "every route outside the wizard sends a fresh install to onboarding" do
    Household.destroy_all

    [
      root_path,           # HomeController          - allow_unauthenticated_access
      select_profile_path, # ProfilesController      - allow_unauthenticated_access
      new_session_path,    # SessionsController      - allow_unauthenticated_access
      recipes_path,        # an ordinary authenticated controller
      meal_plans_path,
      pantry_items_path,
      grocery_list_path,
      admin_root_path,
      family_members_path,
      edit_preferences_path
    ].each do |path|
      get path
      assert_redirected_to onboarding_url,
        "#{path} must route to the wizard before a household exists"
    end
  end

  test "the wizard itself is the one thing reachable on a fresh install" do
    Household.destroy_all

    get onboarding_path
    assert_response :success
  end

  test "end-to-end first boot onboarding flow and profile login" do
    # 1. Clean state: No database records exist
    Household.destroy_all
    assert_equal 0, Household.count
    assert_equal 0, FamilyMember.count

    # 2. Visiting root automatically routes to onboarding family creation
    get root_url
    assert_redirected_to onboarding_url

    follow_redirect!
    assert_response :success
    assert_select "h1", text: /Set Up Your Family Kitchen/i

    # 3. Step 1: Create Household and Primary Organizer Profile (No email/password)
    post onboarding_save_family_url, params: {
      household: {
        name: "The Miller Family",
        breakfast_time: "08:00",
        lunch_time: "12:30",
        dinner_time: "18:30"
      },
      admin_member: {
        name: "Chef Dad",
        pin: "2468",
        avatar_color: "#3B82F6",
        avatar_icon: "chef-hat"
      }
    }

    assert_redirected_to onboarding_members_url
    follow_redirect!
    assert_response :success
    assert_select "h1", text: /Family Kitchen Roster/i
    assert_select "h3", text: "Chef Dad"

    # 4. Step 2: Add additional family members (Mom and Kids)
    post onboarding_add_member_url, params: {
      family_member: {
        name: "Mom",
        role: "admin",
        pin: "1357",
        avatar_color: "#EC4899",
        avatar_icon: "utensils"
      }
    }
    assert_redirected_to onboarding_members_url
    follow_redirect!
    assert_select "h3", text: "Mom"

    post onboarding_add_member_url, params: {
      family_member: {
        name: "Sammy (8)",
        role: "member",
        avatar_color: "#10B981",
        avatar_icon: "smile"
      }
    }
    assert_redirected_to onboarding_members_url
    follow_redirect!
    assert_select "h3", text: "Sammy (8)"

    # Verify 3 family members in the household
    household = Household.last
    assert_equal 3, household.family_members.count

    # 5. Step 3: Starter Recipes Selection
    get onboarding_recipes_url
    assert_response :success
    assert_select "h1", text: /Populate Your Recipe Vault/i

    assert_difference("Recipe.count", 3) do
      post onboarding_save_recipes_url, params: {
        recipe_ids: [ "sheet-pan-fajitas", "spaghetti-bolognese", "friday-pizza-night" ]
      }
    end

    assert_redirected_to onboarding_pantry_url
    follow_redirect!
    assert_response :success
    assert_select "h1", text: /Confirm Your On-Hand Pantry Items/i

    # 6. Step 4: Pantry Shield Staples
    post onboarding_save_pantry_url, params: {
      staple_names: [ "Salt", "Black Pepper", "Olive Oil", "Butter", "Garlic" ]
    }

    assert_redirected_to onboarding_complete_url
    follow_redirect!
    assert_response :success
    assert_select "h1", text: /Welcome to The Miller Family!/i
    assert_select "p", text: /3 Members/i
    assert_select "p", text: /3 Recipes/i
    assert_select "p", text: /5 On-Hand Items/i

    # 7. Visit Meal Planner directly
    meal_plan = household.current_meal_plan
    get meal_plan_url(meal_plan)
    assert_response :success

    # 8. Sign Out / Lock profile
    delete session_url
    assert_redirected_to select_profile_url

    # 9. Accessing planner while signed out redirects to select_profile
    get root_url
    assert_redirected_to select_profile_url

    # 10. Sign in as Sammy (no PIN required)
    sammy = household.family_members.find_by(name: "Sammy (8)")
    post set_profile_url(sammy)
    assert_redirected_to root_url
    follow_redirect!
    assert_redirected_to meal_plan_url(meal_plan)
    follow_redirect!
    assert_response :success

    # 11. Sign in as Chef Dad (PIN required)
    dad = household.family_members.find_by(name: "Chef Dad")
    post set_profile_url(dad), params: { pin: "9999" } # wrong PIN
    assert_redirected_to select_profile_url(pin_member_id: dad.id)

    post set_profile_url(dad), params: { pin: "2468" } # correct PIN
    assert_redirected_to root_url
  end
end
