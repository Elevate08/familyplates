require "test_helper"

# The household's zone is an interpretation layer over UTC storage: nothing
# stored moves, but "today" and "dinner at 6pm" are read against a different
# clock. These pin that separation, and the seeding rule that keeps a travelling
# phone from relocating the kitchen.
class HouseholdTimeZoneTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
  end

  test "an unset zone reads as UTC" do
    @household.update!(time_zone: nil)

    assert_equal "UTC", @household.time_zone_object.name
  end

  test "a set zone is what today and now are measured against" do
    @household.update!(time_zone: "America/Chicago")

    # 02:00 UTC on the 6th is still the evening of the 5th in Chicago.
    travel_to Time.utc(2026, 9, 6, 2, 0, 0) do
      assert_equal Date.new(2026, 9, 5), @household.today
      assert_equal Date.new(2026, 9, 6), Date.current, "the server's day is unchanged"
      assert_equal 21, @household.current_time.hour
    end
  end

  test "daylight saving is applied by the zone, so nothing stored has to move" do
    @household.update!(time_zone: "America/Chicago")

    travel_to Time.utc(2026, 1, 15, 18, 0, 0) do
      assert_equal 12, @household.current_time.hour, "CST, UTC-6"
    end

    travel_to Time.utc(2026, 7, 15, 18, 0, 0) do
      assert_equal 13, @household.current_time.hour, "CDT, UTC-5"
    end
  end

  test "an unrecognized zone is refused rather than silently falling back to UTC" do
    @household.time_zone = "Mars/Olympus_Mons"

    assert_not @household.valid?
    assert_includes @household.errors[:time_zone], "is not a recognized time zone"
  end

  test "a blank zone is allowed - it means nobody has answered yet" do
    @household.time_zone = ""

    assert_predicate @household, :valid?
  end

  test "adopting a zone fills in a blank one" do
    @household.update!(time_zone: nil)

    assert @household.adopt_time_zone("Europe/Lisbon")
    assert_equal "Europe/Lisbon", @household.reload.time_zone
  end

  test "adopting never overwrites an answer already on file" do
    @household.update!(time_zone: "America/Chicago")

    assert_not @household.adopt_time_zone("Asia/Tokyo")
    assert_equal "America/Chicago", @household.reload.time_zone
  end

  test "adopting refuses a name that is not a zone" do
    @household.update!(time_zone: nil)

    assert_not @household.adopt_time_zone("'; DROP TABLE households; --")
    assert_not @household.adopt_time_zone("")
    assert_nil @household.reload.time_zone
  end

  test "the current meal plan follows the household's week, not the server's" do
    @household.update!(time_zone: "America/Chicago")

    # Monday 00:30 UTC is still Sunday evening in Chicago, so the plan on offer
    # is the week that is ending, not the one the server has already started.
    travel_to Time.utc(2026, 9, 7, 0, 30, 0) do
      assert_equal Date.new(2026, 8, 31), @household.current_meal_plan.week_start_date
    end
  end
end
