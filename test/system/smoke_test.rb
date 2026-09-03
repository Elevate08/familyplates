require "application_system_test_case"

# One pass over the pages that carry JavaScript, purely to let the browser
# complain. The assertions are almost incidental - the value is the automatic
# console check in teardown, which is what would have caught the dead Stimulus
# controller and the CSP-blocked scripts.
class SmokeTest < ApplicationSystemTestCase
  setup do
    @admin = family_members(:one)
    @recipe = recipes(:one)
  end

  test "the profile picker loads without browser errors" do
    visit select_profile_path
    assert_text @admin.name
  end

  test "the pages that carry JavaScript load without browser errors" do
    sign_in_as(@admin)

    {
      "meal plan" => meal_plans_path,
      "recipes" => recipes_path,
      "recipe form" => edit_recipe_path(@recipe),
      "pantry" => pantry_items_path,
      "preferences" => edit_preferences_path,
      "admin roster" => admin_family_members_path,
      "admin calendar" => edit_admin_calendar_path
    }.each do |label, path|
      visit path
      assert_no_browser_errors
      assert page.has_css?("body"), "#{label} did not render"
      assert_no_text("We're sorry, but something went wrong")
    end
  end
end
