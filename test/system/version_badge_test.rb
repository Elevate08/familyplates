require "application_system_test_case"

class VersionBadgeTest < ApplicationSystemTestCase
  test "the version is visible on the admin dashboard" do
    sign_in_as(family_members(:one))
    visit admin_root_path

    badge = find("[data-app-version]", wait: 5)

    assert_equal HomeMealPlanner::VERSION, badge.text
    assert badge.visible?, "the version must be readable, not just present in the markup"
  end
end
