require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  test "should get family step on first boot when no household exists" do
    Household.destroy_all
    get onboarding_family_url
    assert_response :success
  end

  test "should redirect family step when household already exists" do
    get onboarding_family_url
    assert_redirected_to select_profile_url
    assert_equal "This kitchen is already configured. Please select your profile.", flash[:alert]
  end

  test "should create household and admin member on save_family without email or password" do
    Household.destroy_all
    assert_difference -> { Household.count } => 1, -> { FamilyMember.count } => 1 do
      post onboarding_save_family_url, params: {
        household: { name: "The Robinson Family", breakfast_time: "07:30", lunch_time: "12:00", dinner_time: "17:30" },
        admin_member: { name: "Captain Chef", pin: "4321", avatar_color: "#3B82F6", avatar_icon: "chef-hat" }
      }
    end

    assert_redirected_to onboarding_members_url
    household = Household.last
    assert_equal "The Robinson Family", household.name
    assert_equal "07:30", household.breakfast_time
    assert_equal "12:00", household.lunch_time
    assert_equal "17:30", household.dinner_time

    admin = FamilyMember.last
    assert_equal "Captain Chef", admin.name
    assert_equal "admin", admin.role
    assert_equal "4321", admin.pin
    assert_equal "#3B82F6", admin.avatar_color
    assert_equal "chef-hat", admin.avatar_icon
  end

  test "should get members roster step when authenticated" do
    sign_in_as(family_members(:one))
    get onboarding_members_url
    assert_response :success
  end

  test "should add additional family member" do
    member_admin = family_members(:one)
    sign_in_as(member_admin)

    assert_difference "FamilyMember.count", 1 do
      post onboarding_add_member_url, params: {
        family_member: {
          name: "Little Chef",
          role: "member",
          avatar_color: "#EC4899",
          avatar_icon: "smile"
        }
      }
    end

    assert_redirected_to onboarding_members_url
    member = FamilyMember.last
    assert_equal "Little Chef", member.name
    assert_equal "member", member.role
    assert_equal "#EC4899", member.avatar_color
    assert_equal "smile", member.avatar_icon
  end

  test "should add additional family member via turbo stream and reset form" do
    member_admin = family_members(:one)
    sign_in_as(member_admin)

    assert_difference "FamilyMember.count", 1 do
      post onboarding_add_member_url, params: {
        family_member: {
          name: "Maya",
          role: "member",
          avatar_color: "#EC4899",
          avatar_icon: "heart"
        }
      }, as: :turbo_stream
    end

    assert_response :success
    assert_includes response.body, "Maya"
    assert_includes response.body, "add-member-form-container"
    assert_includes response.body, "Maya was added successfully!"
    assert_includes response.body, "family-members-list"
  end

  test "should remove non-primary family member" do
    member_admin = family_members(:one)
    sign_in_as(member_admin)

    member = member_admin.household.family_members.create!(name: "Temporary Guest", role: "member", avatar_color: "#10B981")
    assert_difference "FamilyMember.count", -1 do
      delete onboarding_remove_member_url(member)
    end
    assert_redirected_to onboarding_members_url
  end

  test "should get recipes step" do
    sign_in_as(family_members(:one))
    get onboarding_recipes_url
    assert_response :success
  end

  test "should save selected starter recipes" do
    sign_in_as(family_members(:one))
    assert_difference("Recipe.count", 2) do
      post onboarding_save_recipes_url, params: {
        recipe_ids: [ "sheet-pan-fajitas", "spaghetti-bolognese" ]
      }
    end
    assert_redirected_to onboarding_pantry_url
  end

  test "should get pantry step" do
    sign_in_as(family_members(:one))
    get onboarding_pantry_url
    assert_response :success
  end

  test "should save pantry staples and redirect to complete" do
    sign_in_as(family_members(:one))
    post onboarding_save_pantry_url, params: {
      staple_names: [ "Salt", "Black Pepper", "Olive Oil" ]
    }
    assert_redirected_to onboarding_complete_url
  end

  test "should get complete step" do
    sign_in_as(family_members(:one))
    get onboarding_complete_url
    assert_response :success
  end
end
