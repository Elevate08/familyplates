# When a household shops: every week, every 2 weeks or every month, counted
# from one day the household shops (the anchor). A shopping period runs from a
# shopping day to the day before the next one.
#
# Weekly uses the anchor's weekday, fortnightly the anchor plus or minus whole
# multiples of 14 days, monthly the anchor's day of the month (clamped to the
# month's last day, so a 31st shops on Feb 28 or 29).
class ShoppingSchedule
  FREQUENCIES = %w[weekly fortnightly monthly].freeze
  # A Saturday, so a household that never chose shops weekly on Saturday.
  DEFAULT_ANCHOR = Date.new(2026, 1, 3)

  attr_reader :frequency, :anchor

  def initialize(frequency, anchor)
    @frequency = FREQUENCIES.include?(frequency.to_s) ? frequency.to_s : "weekly"
    @anchor = anchor.to_date
  end

  DEFAULT = new("weekly", DEFAULT_ANCHOR)

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
