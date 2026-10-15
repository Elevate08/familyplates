require "test_helper"

class ShoppingScheduleTest < ActiveSupport::TestCase
  def d(string) = Date.parse(string)

  def period(schedule, date)
    range = schedule.period(d(date))
    [ range.begin.iso8601, range.end.iso8601 ]
  end

  # @card-62.9
  test "the default is weekly on Saturday" do
    assert_equal "weekly", ShoppingSchedule::DEFAULT.frequency
    assert_equal 6, ShoppingSchedule::DEFAULT.anchor.wday
  end

  test "weekday choices run Monday to Sunday" do
    assert_equal %w[Monday Tuesday Wednesday Thursday Friday Saturday Sunday],
      ShoppingSchedule.weekday_choices.map(&:first)
    assert_equal %w[1 2 3 4 5 6 0], ShoppingSchedule.weekday_choices.map(&:last)
  end

  test "a weekly weekday lands on the default anchor's week and a matching one stays put" do
    assert_equal d("2026-01-03"), ShoppingSchedule.anchor_on_weekday(6, current: d("2026-05-04"), frequency: "weekly")
    assert_equal d("2026-01-09"), ShoppingSchedule.anchor_on_weekday(5, current: d("2026-01-03"), frequency: "weekly")
    assert_equal d("2026-01-04"), ShoppingSchedule.anchor_on_weekday(0, current: d("2026-01-03"), frequency: "weekly")
    assert_equal d("2026-10-17"), ShoppingSchedule.anchor_on_weekday(6, current: d("2026-10-17"), frequency: "weekly")
  end

  test "a fortnightly weekday slides by at most three days and keeps the 14-day step" do
    anchor = ShoppingSchedule.anchor_on_weekday(5, current: d("2026-10-03"), frequency: "fortnightly")
    assert_equal d("2026-10-02"), anchor

    schedule = ShoppingSchedule.new("fortnightly", anchor)
    assert_equal [ "2026-10-02", "2026-10-15" ], period(schedule, "2026-10-14")
    assert_equal [ "2026-10-16", "2026-10-29" ], period(schedule, "2026-10-16")
    assert_equal [ "2026-09-18", "2026-10-01" ], period(schedule, "2026-10-01")

    assert_equal d("2026-10-03"), ShoppingSchedule.anchor_on_weekday(6, current: d("2026-10-03"), frequency: "fortnightly")
    assert_equal d("2026-09-30"), ShoppingSchedule.anchor_on_weekday(3, current: d("2026-10-03"), frequency: "fortnightly")
  end

  test "a month-day choice stores that day and still clamps shorter months" do
    assert_equal d("2026-02-28"), ShoppingSchedule.anchor_on_month_day(28, current: d("2026-02-28"))

    anchor = ShoppingSchedule.anchor_on_month_day(31, current: d("2026-01-20"))
    assert_equal d("2026-01-31"), anchor
    monthly = ShoppingSchedule.new("monthly", anchor)
    assert_equal [ "2027-02-28", "2027-03-30" ], period(monthly, "2027-03-15")
    assert_equal [ "2028-02-29", "2028-03-30" ], period(monthly, "2028-02-29")
  end

  # @card-62.8
  test "weekly periods start on the anchor's weekday, today included" do
    weekly = ShoppingSchedule.new("weekly", d("2026-01-03")) # Saturday

    assert_equal [ "2026-10-10", "2026-10-16" ], period(weekly, "2026-10-14") # Wednesday
    assert_equal [ "2026-10-17", "2026-10-23" ], period(weekly, "2026-10-17") # the shopping day
    assert_equal [ "2026-10-10", "2026-10-16" ], period(weekly, "2026-10-16") # the day before
    assert_equal [ "2026-10-10", "2026-10-16" ], period(weekly, "2026-10-10")
  end

  # @card-62.8
  test "weekly counts from any anchor weekday, including one in the future" do
    monday = ShoppingSchedule.new("weekly", d("2030-01-07"))
    assert_equal [ "2026-10-12", "2026-10-18" ], period(monday, "2026-10-14")
    assert_equal [ "2026-10-12", "2026-10-18" ], period(monday, "2026-10-12")
  end

  # @card-62.8
  test "fortnightly periods alternate from the anchor, on both sides of it" do
    fortnight = ShoppingSchedule.new("fortnightly", d("2026-10-03"))

    assert_equal [ "2026-10-03", "2026-10-16" ], period(fortnight, "2026-10-03")
    assert_equal [ "2026-10-03", "2026-10-16" ], period(fortnight, "2026-10-16")
    assert_equal [ "2026-10-17", "2026-10-30" ], period(fortnight, "2026-10-17")
    assert_equal [ "2026-10-17", "2026-10-30" ], period(fortnight, "2026-10-20")
    # before the anchor
    assert_equal [ "2026-09-19", "2026-10-02" ], period(fortnight, "2026-10-02")
    assert_equal [ "2026-09-19", "2026-10-02" ], period(fortnight, "2026-09-19")
    assert_equal [ "2026-09-05", "2026-09-18" ], period(fortnight, "2026-09-18")
    # across the year boundary
    assert_equal [ "2026-12-26", "2027-01-08" ], period(fortnight, "2027-01-01")
  end

  # @card-62.8
  test "monthly periods start on the anchor's day of the month" do
    monthly = ShoppingSchedule.new("monthly", d("2026-01-20"))

    assert_equal [ "2026-09-20", "2026-10-19" ], period(monthly, "2026-10-14")
    assert_equal [ "2026-10-20", "2026-11-19" ], period(monthly, "2026-10-20")
    assert_equal [ "2026-09-20", "2026-10-19" ], period(monthly, "2026-10-19")
    assert_equal [ "2026-11-20", "2026-12-19" ], period(monthly, "2026-12-01")
  end

  # @card-62.8
  test "monthly periods cross the year boundary" do
    monthly = ShoppingSchedule.new("monthly", d("2026-01-20"))

    assert_equal [ "2026-12-20", "2027-01-19" ], period(monthly, "2026-12-31")
    assert_equal [ "2026-12-20", "2027-01-19" ], period(monthly, "2027-01-05")
    assert_equal [ "2027-01-20", "2027-02-19" ], period(monthly, "2027-01-20")
  end

  # @card-62.8
  test "a monthly anchor on the 31st shops on the last day of shorter months" do
    monthly = ShoppingSchedule.new("monthly", d("2026-01-31"))

    assert_equal [ "2027-01-31", "2027-02-27" ], period(monthly, "2027-02-10")
    assert_equal [ "2027-02-28", "2027-03-30" ], period(monthly, "2027-02-28")
    assert_equal [ "2027-02-28", "2027-03-30" ], period(monthly, "2027-03-15")
    assert_equal [ "2027-03-31", "2027-04-29" ], period(monthly, "2027-03-31")
    assert_equal [ "2027-04-30", "2027-05-30" ], period(monthly, "2027-05-02")
    assert_equal [ "2027-03-31", "2027-04-29" ], period(monthly, "2027-04-29")
  end

  # @card-62.8
  test "a leap year's February has a 29th shopping day" do
    monthly = ShoppingSchedule.new("monthly", d("2026-01-31"))

    assert_equal [ "2028-01-31", "2028-02-28" ], period(monthly, "2028-02-15")
    assert_equal [ "2028-02-29", "2028-03-30" ], period(monthly, "2028-02-29")
    assert_equal [ "2028-01-31", "2028-02-28" ], period(monthly, "2028-02-28")
  end

  # @card-62.8
  test "previous and next periods are the neighbours of the one containing the date" do
    monthly = ShoppingSchedule.new("monthly", d("2026-01-31"))
    assert_equal d("2027-01-31")..d("2027-02-27"), monthly.previous_period(d("2027-03-05"))
    assert_equal d("2027-03-31")..d("2027-04-29"), monthly.next_period(d("2027-03-05"))

    weekly = ShoppingSchedule::DEFAULT
    assert_equal d("2026-10-03")..d("2026-10-09"), weekly.previous_period(d("2026-10-14"))
    assert_equal d("2026-10-17")..d("2026-10-23"), weekly.next_period(d("2026-10-14"))
  end

  # @card-62.8
  test "every date falls in exactly one period and periods tile with no gaps" do
    [ [ "weekly", "2026-01-03" ], [ "fortnightly", "2026-03-15" ], [ "monthly", "2026-01-31" ], [ "monthly", "2026-05-30" ] ].each do |frequency, anchor|
      schedule = ShoppingSchedule.new(frequency, d(anchor))
      d("2027-12-20").upto(d("2028-03-10")) do |date|
        range = schedule.period(date)
        assert range.cover?(date), "#{frequency} #{anchor} #{date}"
        assert_equal range.end + 1, schedule.period(range.end + 1).begin
      end
    end
  end
end
