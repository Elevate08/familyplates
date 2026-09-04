# frozen_string_literal: true

require "test_helper"

class HostedModeTenancyTest < ActionDispatch::IntegrationTest
  setup do
    FamilyPlates.config.reset!
    FamilyPlates.config.mode = "hosted"
  end

  teardown do
    FamilyPlates.config.reset!
  end

  test "unauthenticated access in hosted mode redirects to session or signup" do
    # Root redirects to session
    get root_path
    assert_redirected_to new_session_path
    assert_nil flash[:alert]

    # Select profile redirects to session
    get select_profile_path
    assert_redirected_to new_session_path
    assert_equal "Please sign in to select a profile.", flash[:alert]

    # Setup wizard in hosted mode redirects unauthenticated visitors to signup
    get onboarding_path
    assert_redirected_to new_signup_path
    assert_equal "In hosted mode, please sign up to create a household.", flash[:alert]
  end

  test "tampered or unauthenticated active_family_member_id cookie is stripped in hosted mode" do
    member = family_members(:one)

    # Set member cookie directly without a valid user session
    set_signed_cookie(:active_family_member_id, member.id)

    get select_profile_path
    assert_redirected_to new_session_path
    assert_nil get_signed_cookie(:active_family_member_id)
  end

  test "end-to-end hosted signup, verification, and per-tenant onboarding" do
    assert_enqueued_emails 1 do
      post signup_path, params: {
        household_name: "The Bakers",
        organizer_name: "Sarah Baker",
        email: "sarah@bakers.test",
        pin: "5678"
      }
    end

    assert_redirected_to verify_signup_path
    magic_code = MagicCode.find_by!(email: "sarah@bakers.test")

    # Verify code
    assert_difference -> { Household.count } => 1, -> { User.count } => 1, -> { FamilyMember.count } => 1 do
      post verify_signup_path, params: { code: magic_code.code }
    end

    assert_redirected_to onboarding_recipes_path
    user = User.find_by!(email: "sarah@bakers.test")
    household = Household.find_by!(name: "The Bakers")
    organizer = household.family_members.find_by!(name: "Sarah Baker")

    assert_equal "admin", organizer.role
    assert organizer.verify_pin("5678")
    assert_not household.onboarded?

    # Save starter recipes during per-tenant onboarding
    starter_file = YAML.load_file(Rails.root.join("config/starter_recipes.yml"))
    starter_recipe_id = starter_file["starter_recipes"].first["id"]
    starter_recipe_title = starter_file["starter_recipes"].first["title"]

    assert_difference -> { household.recipes.count } => 1 do
      post onboarding_save_recipes_path, params: { recipe_ids: [ starter_recipe_id ] }
    end

    assert_redirected_to onboarding_pantry_path
    recipe = household.recipes.find_by!(title: starter_recipe_title)
    assert_equal household, recipe.household

    # Save pantry staples
    assert_difference -> { household.pantry_items.staples.count } => 2 do
      post onboarding_save_pantry_path, params: { staple_names: [ "Olive Oil", "Garlic" ] }
    end

    assert_redirected_to onboarding_complete_path

    # Complete onboarding
    get onboarding_complete_path
    assert_response :success
    assert household.reload.onboarded?

    # Attempting to visit onboarding again redirects to root
    get onboarding_path
    assert_redirected_to root_path
    assert_equal "Your family kitchen is already set up.", flash[:alert]
  end

  test "signed-in user cannot access another tenant's profiles or data" do
    # Household 1 & User 1
    h1 = households(:one)
    u1 = User.create!(email: "user1@example.com")
    m1 = h1.family_members.create!(name: "Parent 1", role: "admin", pin: "1111", user: u1, avatar_color: "#3B82F6", avatar_icon: "star")

    # Household 2 & User 2
    h2 = households(:two)
    u2 = User.create!(email: "user2@example.com")
    m2 = h2.family_members.create!(name: "Parent 2", role: "admin", pin: "2222", user: u2, avatar_color: "#10B981", avatar_icon: "heart")
    child2 = h2.family_members.create!(name: "Child 2", role: "member", avatar_color: "#F59E0B", avatar_icon: "smile")

    # Sign in as User 1
    session_record = u1.sessions.create!(token: SecureRandom.hex(32), kind: "browser")
    set_signed_cookie(:session_token, session_record.token)
    set_signed_cookie(:active_family_member_id, m1.id)

    # Profile picker only lists Household 1 members
    get select_profile_path
    assert_response :success
    assert_select "div", text: /Parent 1/
    assert_no_match(/Parent 2/, response.body)
    assert_no_match(/Child 2/, response.body)

    # Cannot switch into Household 2 member
    post set_profile_path(child2)
    assert_response :not_found

    # Forging an active_family_member_id cookie belonging to another household is stripped
    set_signed_cookie(:active_family_member_id, child2.id)
    get select_profile_path
    assert_response :success
    assert_nil get_signed_cookie(:active_family_member_id)
  end

  private

  def set_signed_cookie(key, value)
    jar = ActionDispatch::Cookies::CookieJar.build(ActionDispatch::TestRequest.create, {})
    jar.signed[key] = value
    cookies[key] = jar[key]
  end

  def get_signed_cookie(key)
    raw = cookies[key]
    return nil if raw.blank?
    jar = ActionDispatch::Cookies::CookieJar.build(ActionDispatch::TestRequest.create, key.to_s => raw)
    jar.signed[key]
  end
end
