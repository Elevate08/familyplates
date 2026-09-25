require "test_helper"

# The zone can only come from the device: the request carries none, and the
# host's own TZ describes the machine rather than the family. This covers the
# seeding endpoint the browser posts to, and the rules that keep it from being
# a way to move someone else's kitchen.
class HouseholdTimeZoneDetectionTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @household.update!(time_zone: nil)
    @admin = family_members(:one)
    @member = family_members(:two)
  end

  test "a device reporting its zone seeds a household that has none" do
    sign_in_as(@admin)

    post household_time_zone_url, params: { time_zone: "America/Chicago" }

    assert_response :no_content
    assert_equal "America/Chicago", @household.reload.time_zone
  end

  test "any member's device can answer - whoever is standing in the kitchen" do
    sign_in_as(@member)

    post household_time_zone_url, params: { time_zone: "Europe/Berlin" }

    assert_equal "Europe/Berlin", @household.reload.time_zone
  end

  test "a zone already on file is never overwritten by a device" do
    @household.update!(time_zone: "America/Chicago")
    sign_in_as(@admin)

    post household_time_zone_url, params: { time_zone: "Asia/Tokyo" }

    assert_response :no_content
    assert_equal "America/Chicago", @household.reload.time_zone,
                 "a phone that travels must not relocate the kitchen"
  end

  test "a name that is not a zone is discarded" do
    sign_in_as(@admin)

    post household_time_zone_url, params: { time_zone: "Nowhere/Nothing" }

    assert_response :no_content
    assert_nil @household.reload.time_zone
  end

  test "an unauthenticated request sets nothing" do
    post household_time_zone_url, params: { time_zone: "Asia/Tokyo" }

    assert_response :redirect
    assert_nil @household.reload.time_zone
  end

  test "the detector is rendered only while the household has no zone" do
    sign_in_as(@admin)

    get root_url
    follow_redirect! while response.redirect?
    assert_select "[data-controller='time-zone-detector']"

    @household.update!(time_zone: "America/Chicago")
    get meal_plans_url
    follow_redirect! while response.redirect?
    assert_select "[data-controller='time-zone-detector']", false,
                  "asking again once answered is noise on every page load"
  end

  test "an admin can set and change the zone from household settings" do
    sign_in_as(@admin)

    patch admin_household_url, params: { household: { time_zone: "Australia/Sydney" } }
    assert_equal "Australia/Sydney", @household.reload.time_zone

    # Unlike the detector, the form is how a zone already set gets corrected.
    patch admin_household_url, params: { household: { time_zone: "America/Denver" } }
    assert_equal "America/Denver", @household.reload.time_zone
  end

  test "the settings form refuses a zone that does not exist" do
    sign_in_as(@admin)

    patch admin_household_url, params: { household: { time_zone: "Middle/Earth" } }

    assert_response :unprocessable_entity
    assert_nil @household.reload.time_zone
  end
end
