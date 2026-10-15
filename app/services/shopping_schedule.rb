# When a household shops: every week, every 2 weeks or every month, counted
# from one day the household shops (the anchor). A shopping period runs from a
# shopping day to the day before the next one.
#
# Weekly uses the anchor's weekday, fortnightly the anchor plus or minus whole
# multiples of 14 days, monthly the anchor's day of the month (clamped to the
# month's last day, so a 31st shops on Feb 28 or 29).
#
# The settings form does not ask for a calendar date. Weekly and fortnightly
# ask for a weekday and store it as an anchor (see .anchor_on_weekday).
# Monthly asks for a day of the month (see .anchor_on_month_day).
class ShoppingSchedule
  FREQUENCIES = %w[weekly fortnightly monthly].freeze
  # A Saturday, so a household that never chose shops weekly on Saturday.
  DEFAULT_ANCHOR = Date.new(2026, 1, 3)
  # Monday through Sunday, the order the planner prints a week.
  WEEKDAY_ORDER = [ 1, 2, 3, 4, 5, 6, 0 ].freeze

  attr_reader :frequency, :anchor

  def initialize(frequency, anchor)
    @frequency = FREQUENCIES.include?(frequency.to_s) ? frequency.to_s : "weekly"
    @anchor = anchor.to_date
  end

  DEFAULT = new("weekly", DEFAULT_ANCHOR)

  def self.weekday_choices
    WEEKDAY_ORDER.map { |wday| [ Date::DAYNAMES[wday], wday.to_s ] }
  end

  def self.month_day_choices
    (1..31).map { |day| [ day.ordinalize, day.to_s ] }
  end

  # Anchor date for a weekday chosen on the settings form.
  #
  # Weekly has no second week to land in, so a different weekday uses the week
  # of DEFAULT_ANCHOR (Saturday stays 2026-01-03). An anchor that already falls
  # on the chosen weekday is kept, which is what leaves an existing Saturday
  # household on that Saturday.
  #
  # Fortnightly's phase is the anchor date itself. The chosen weekday slides
  # that date by at most three days, so the shopping days stay 14 apart and
  # the household does not flip to the other week.
  def self.anchor_on_weekday(wday, current:, frequency:)
    current = (current || DEFAULT_ANCHOR).to_date
    wday = Integer(wday)
    return current if current.wday == wday

    if frequency.to_s == "fortnightly"
      delta = (wday - current.wday) % 7
      delta -= 7 if delta > 3
      current + delta
    else
      DEFAULT_ANCHOR + ((wday - DEFAULT_ANCHOR.wday) % 7)
    end
  end

  # Monthly uses the day of the month, not a weekday. January has 31 days, so
  # the stored anchor can hold a 29th, 30th or 31st for the short-month clamp.
  # An anchor that already falls on that day is kept.
  def self.anchor_on_month_day(day, current:)
    current = (current || DEFAULT_ANCHOR).to_date
    day = Integer(day)
    return current if current.day == day

    Date.new(current.year, 1, day)
  end

  # The latest shopping day on or before the date.
  def start_on_or_before(date)
    case frequency
    when "weekly" then date - ((date - anchor).to_i % 7)
    when "fortnightly" then date - ((date - anchor).to_i % 14)
    else
      this_month = monthly_day(date.year, date.month)
      this_month <= date ? this_month : monthly_day_in(date << 1)
    end
  end

  # The first shopping day after the given shopping day.
  def start_after(start)
    case frequency
    when "weekly" then start + 7
    when "fortnightly" then start + 14
    else monthly_day_in(start >> 1)
    end
  end

  # The shopping period containing the date, as a Range of dates.
  def period(date)
    start = start_on_or_before(date)
    start..(start_after(start) - 1)
  end

  def previous_period(date)
    period(period(date).begin - 1)
  end

  def next_period(date)
    period(period(date).end + 1)
  end

  private

  def monthly_day_in(date)
    monthly_day(date.year, date.month)
  end

  def monthly_day(year, month)
    Date.new(year, month, [ anchor.day, Time.days_in_month(month, year) ].min)
  end
end
