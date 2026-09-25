require "test_helper"

# The Key Assumption behind dropping the Household.installation fallback from
# current_household: "confirm the removal does not break unauthenticated views
# (navbar, landing, onboarding)."
#
# Every page here renders the shared navbar, which is where an anonymous request
# would blow up on a nil household if anything still assumed one was present.
class UnauthenticatedViewsHostedTest < ActionDispatch::IntegrationTest
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
