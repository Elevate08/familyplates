# The shopping period a grocery list covers: a first and last date, plus the
# presets and previous/next steps that move between periods.
class GroceryRange
  MAX_DAYS = 42

  PRESETS = [
    [ :this_week, "This week" ],
    [ :next_week, "Next week" ],
    [ :from_today, "From today" ],
    [ :this_month, "This month" ],
    [ :next_month, "Next month" ]
  ].freeze

  attr_reader :from, :to, :today

  # The range shown when the address names none. The one place to change it.
  def self.default(today)
    new(today.beginning_of_week, today.beginning_of_week + 6.days, today: today)
  end

  # Builds from request params. Anything unusable falls back to the default; a
  # range longer than MAX_DAYS is cut to MAX_DAYS from its first day (see #clamped?).
  def self.from_params(from_param, to_param, today:)
    from = MealPlanSlot.parse_date(from_param)
    to = MealPlanSlot.parse_date(to_param)
    return default(today) if from.nil? || to.nil? || to < from

    new(from, to, today: today)
  end

  def initialize(from, to, today:)
    @today = today
    @requested_to = to
    @from = from
    @to = [ to, from + (MAX_DAYS - 1).days ].min
  end

  def clamped?
    @to != @requested_to
  end

  def days
    (to - from).to_i + 1
  end

  def to_range
    from..to
  end

  def label
    if from.year != to.year
      "#{from.strftime('%b %-d, %Y')} – #{to.strftime('%b %-d, %Y')}"
    elsif from == to
      from.strftime("%b %-d, %Y")
    else
      "#{from.strftime('%b %-d')} – #{to.strftime('%b %-d, %Y')}"
    end
  end

  def params
    { from: from.iso8601, to: to.iso8601 }
  end

  def preset(key)
    case key
    when :this_week then span(today.beginning_of_week, today.beginning_of_week + 6.days)
    when :next_week then span(today.beginning_of_week + 7.days, today.beginning_of_week + 13.days)
    when :from_today then span(today, today.beginning_of_week + 6.days)
    when :this_month then span(today.beginning_of_month, today.end_of_month)
    when :next_month then span((today + 1.month).beginning_of_month, (today + 1.month).end_of_month)
    end
  end

  # [[key, label, GroceryRange]] in display order
  def presets
    PRESETS.map { |key, name| [ key, name, preset(key) ] }
  end

  # The first preset that is exactly this range, or nil for a custom one.
  def active_preset
    presets.find { |_key, _name, range| range == self }&.first
  end

  def calendar_month?
    from == from.beginning_of_month && to == from.end_of_month
  end

  def previous
    calendar_month? ? month_at(from << 1) : shifted(-days)
  end

  def following
    calendar_month? ? month_at(from >> 1) : shifted(days)
  end

  def ==(other)
    other.is_a?(GroceryRange) && from == other.from && to == other.to
  end

  private

  def span(from, to)
    self.class.new(from, to, today: today)
  end

  def month_at(date)
    span(date.beginning_of_month, date.end_of_month)
  end

  def shifted(offset)
    span(from + offset.days, to + offset.days)
  end
end
