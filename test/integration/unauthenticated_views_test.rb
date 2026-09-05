require "test_helper"

# The Key Assumption behind dropping the Household.installation fallback from
# current_household: "confirm the removal does not break unauthenticated views
# (navbar, landing, onboarding)."
#
# Every page here renders the shared navbar, which is where an anonymous request
# would blow up on a nil household if anything still assumed one was present.
class UnauthenticatedViewsTest < ActionDispatch::IntegrationTest
  test "the profile picker renders for a stranger" do
    get select_profile_url

    assert_response :success
    assert_select "nav", minimum: 1, message: "the navbar must render without a household"
  end

  test "the picker names no household to a stranger" do
    get select_profile_url

    assert_response :success
    assert_no_match(/Spencer Family/, response.body,
      "the household name is signed-in chrome; a stranger at the door has not chosen one yet")
  end

  test "the landing page sends a stranger to the picker" do
    get root_url

    assert_redirected_to select_profile_url
    follow_redirect!
    assert_response :success
  end

  test "signing out returns to a working picker" do
    sign_in_as(family_members(:one))
    sign_out

    get select_profile_url
    assert_response :success
  end

  # Both links in the picker's footer need a session: /preferences edits the
  # signed-in member, and the admin one is already guarded. Offering a stranger
  # a link that can only bounce them back to the page they are on is a dead end
  # dressed up as an option.
  test "the picker offers a stranger no links that require a session" do
    get select_profile_url

    assert_response :success
    assert_select "a[href=?]", preferences_path, false,
      "My Preferences needs a signed-in member, so a stranger should not be offered it"
    assert_select "a[href=?]", admin_root_path, false
  end

  test "the picker still offers preferences to a signed-in member" do
    sign_in_as(family_members(:two))

    get select_profile_url

    assert_response :success
    assert_select "a[href=?]", preferences_path, true,
      "switching profiles is done from this page, so the link belongs here when signed in"
  end

  test "following the stranger's preferences link would only bounce them back" do
    get edit_preferences_url

    assert_redirected_to select_profile_url
  end

  test "the wizard renders on a fresh install" do
    Household.destroy_all

    get onboarding_url

    assert_response :success
    assert_select "nav", minimum: 1, message: "the navbar must render with no household at all"
  end

  test "the wizard offers setup rather than a profile switch on a fresh install" do
    Household.destroy_all

    get onboarding_url

    assert_response :success
    assert_match(/Set Up Kitchen/, response.body)
  end

  test "contact support is not visible in appliance mode" do
    FamilyPlates.config.mode = "appliance"
    sign_in_as(family_members(:one))

    get root_url
    follow_redirect!

    assert_response :success
    assert_select "a[href=?]", support_threads_path, false,
      "Contact support should not be visible in appliance mode"
  ensure
    FamilyPlates.config.reset!
  end

  test "contact support is visible in hosted mode for signed-in members" do
    FamilyPlates.config.mode = "hosted"
    user = User.create!(email: "member@example.com")
    member = family_members(:one)
    member.update!(user: user)
    sign_in_user(user)
    sign_in_as(member)

    get root_url
    follow_redirect!
    follow_redirect! if response.redirect?

    assert_response :success
    assert_select "a[href=?]", support_threads_path, true,
      "Contact support should be visible in hosted mode"
  ensure
    FamilyPlates.config.reset!
  end
end
