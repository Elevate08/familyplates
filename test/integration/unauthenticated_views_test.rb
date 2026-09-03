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
end
