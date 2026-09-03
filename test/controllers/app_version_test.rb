require "test_helper"

# The version has to be readable off a running install. "Which build is this?"
# is the first question when something misbehaves in production, and until now
# the only answer lived in a git tag the deployed container does not carry.
class AppVersionTest < ActionDispatch::IntegrationTest
  test "the constant matches the VERSION file" do
    on_disk = File.read(Rails.root.join("VERSION")).strip

    assert_equal on_disk, HomeMealPlanner::VERSION
  end

  test "the VERSION file holds a bare semver number" do
    raw = File.read(Rails.root.join("VERSION"))

    assert_match(/\A\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\n?\z/, raw,
      "VERSION must be just the number, e.g. 1.2.0 - no leading v, no commentary")
  end

  test "the CHANGELOG's newest entry matches the VERSION file" do
    # Release drift is silent otherwise: the tag, the changelog heading and the
    # number on the page have to agree, and only this notices when they stop.
    heading = File.readlines(Rails.root.join("CHANGELOG.md"))
                  .find { |line| line.start_with?("## [") }

    assert heading, "precondition: the CHANGELOG has a versioned heading"
    assert_includes heading, "[v#{HomeMealPlanner::VERSION}]",
      "CHANGELOG's newest entry is #{heading.strip.inspect} but VERSION says #{HomeMealPlanner::VERSION}"
  end

  test "an organizer sees the version on the admin dashboard" do
    sign_in_as(family_members(:one))

    get admin_root_url

    assert_response :success
    assert_select "[data-app-version]", text: HomeMealPlanner::VERSION
  end

  test "the version is not exposed to a member who cannot reach admin" do
    sign_in_as(family_members(:two))
    assert_not family_members(:two).admin?, "precondition: fixture two is a plain member"

    get admin_root_url

    assert_response :redirect
  end
end
