require "application_system_test_case"

# The only end-to-end check of the one path that can actually tell this app what
# o'clock it is. A request test can post the endpoint and a unit test can seed
# the model, but neither proves the browser reads its own zone and gets it
# through - and that round trip is the whole mechanism.
class TimeZoneDetectionTest < ApplicationSystemTestCase
  setup do
    @household = households(:one)
    @household.update!(time_zone: nil)
  end

  test "a browser reports its own zone and the household adopts it" do
    sign_in_as(family_members(:one))

    expected = page.evaluate_script("Intl.DateTimeFormat().resolvedOptions().timeZone")
    assert expected.present?, "precondition: this browser knows its zone"

    assert_equal expected, poll_for_time_zone,
                 "the detector never got the zone to the server"
  end

  test "nothing is posted once a zone is on file" do
    @household.update!(time_zone: "America/Chicago")

    sign_in_as(family_members(:one))
    visit meal_plans_path

    assert_no_selector "[data-controller='time-zone-detector']", visible: :all
    assert_equal "America/Chicago", @household.reload.time_zone
  end

  private

  # The post is fire-and-forget, so there is no DOM change to wait on.
  def poll_for_time_zone
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5

    loop do
      zone = @household.reload.time_zone
      return zone if zone.present?
      return nil if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end
  end
end
