require "test_helper"

class IcalGeneratorTest < ActiveSupport::TestCase
  test "generates valid iCal feed with VEVENTs" do
    household = households(:one)
    feed = IcalGenerator.call(household)

    assert_includes feed, "BEGIN:VCALENDAR"
    assert_includes feed, "VERSION:2.0"
    assert_includes feed, "BEGIN:VEVENT"
    assert_includes feed, "SUMMARY:🍽️ [Dinner] Taco Tuesday"
    assert_includes feed, "END:VCALENDAR"
  end
end
