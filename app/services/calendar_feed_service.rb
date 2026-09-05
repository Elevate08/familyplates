# Generates RFC 5545 compliant iCalendar (.ics) feeds for household meal plans.
#
# Supports:
# - Full household meal schedules or individual member's cooking assignments
# - Correct UTC timestamps derived from household meal preferences and timezone
# - Rich summaries, cook attribution, ingredients previews, and recipe URLs
# - RFC 5545 line folding (<= 75 octets) and character escaping
# - Non-blocking transparent events (TRANSP:TRANSPARENT)
class CalendarFeedService
  CRLF = "\r\n".freeze

  attr_reader :household, :member, :base_url

  def initialize(household, member: nil, base_url: nil)
    @household = household
    @member = member
    @base_url = base_url
  end

  def calendar_name
    if member
      "FamilyPlates - #{member.name}'s Cooking"
    else
      "FamilyPlates - #{household.name}"
    end
  end

  def generate_ics
    slots = scoped_slots

    lines = []
    lines << "BEGIN:VCALENDAR"
    lines << "VERSION:2.0"
    lines << "PRODID:-//FamilyPlates//Meal Planner//EN"
    lines << "CALSCALE:GREGORIAN"
    lines << "METHOD:PUBLISH"
    lines << "X-WR-CALNAME:#{escape_text(calendar_name)}"
    lines << "X-WR-CALDESC:#{escape_text("Family meal schedule from FamilyPlates")}"
    lines << "X-WR-TIMEZONE:#{household.time_zone_object.name}"
    lines << "REFRESH-INTERVAL;VALUE=DURATION:PT1H"
    lines << "X-PUBLISHED-TTL:PT1H"

    slots.each do |slot|
      next if slot.display_title == "No Meal Planned"

      start_time, end_time = calculate_slot_times(slot)
      summary = build_summary(slot)
      description = build_description(slot)
      url = build_url(slot)

      lines << "BEGIN:VEVENT"
      lines << "UID:meal-plan-slot-#{slot.id}@familyplates"
      lines << "DTSTAMP:#{Time.current.utc.strftime('%Y%m%dT%H%M%SZ')}"
      lines << "DTSTART:#{start_time.utc.strftime('%Y%m%dT%H%M%SZ')}"
      lines << "DTEND:#{end_time.utc.strftime('%Y%m%dT%H%M%SZ')}"
      lines << "SUMMARY:#{escape_text(summary)}"
      lines << "DESCRIPTION:#{escape_text(description)}"
      lines << "URL:#{escape_text(url)}" if url.present?
      lines << "STATUS:CONFIRMED"
      lines << "TRANSP:TRANSPARENT"
      lines << "END:VEVENT"
    end

    lines << "END:VCALENDAR"

    fold_lines(lines).join(CRLF) + CRLF
  end

  def calculate_slot_times(slot)
    time_str = slot.scheduled_time.presence ||
      case slot.meal_type
      when "breakfast" then household.breakfast_time.presence || "08:00"
      when "lunch"     then household.lunch_time.presence || "12:30"
      else                  household.dinner_time.presence || "18:00"
      end

    duration_minutes = case slot.meal_type
    when "breakfast" then 45
    when "lunch"     then 45
    else                  60
    end

    hour, min = time_str.split(":").map(&:to_i)
    # The household's clock, not the server's: a feed generated on a UTC box was
    # publishing "dinner at 6pm" as 18:00 UTC, which lands mid-afternoon in a
    # Chicago subscriber's calendar.
    start_time = household.time_zone_object.local(slot.date.year, slot.date.month, slot.date.day, hour, min, 0)
    end_time = start_time + duration_minutes.minutes

    [ start_time, end_time ]
  end

  def build_summary(slot)
    meal_type_tag = slot.meal_type.to_s.capitalize
    cook_tag = slot.cook_name.present? ? " (Cook: #{slot.cook_name})" : ""
    "🍽️ #{meal_type_tag}: #{slot.display_title}#{cook_tag}"
  end

  def build_description(slot)
    desc_lines = []
    desc_lines << "👨‍🍳 Cook: #{slot.cook_name || 'Family'}"

    if slot.recipe
      r = slot.recipe
      desc_lines << "⏱️ Prep: #{r.prep_time}m | Cook: #{r.cook_time}m | Servings: #{r.servings}"
      if r.recipe_ingredients.any?
        desc_lines << ""
        desc_lines << "📋 Ingredients:"
        r.recipe_ingredients.each do |ing|
          qty = ing.quantity.present? ? "#{ing.quantity} " : ""
          unit = ing.unit.present? ? "#{ing.unit} " : ""
          desc_lines << "• #{qty}#{unit}#{ing.name}".strip
        end
      end
    end

    if slot.notes.present?
      desc_lines << ""
      desc_lines << "📝 Notes: #{slot.notes}"
    end

    if base_url.present?
      desc_lines << ""
      if slot.recipe
        desc_lines << "🔗 Recipe: #{base_url.chomp('/')}/recipes/#{slot.recipe.to_param}"
      else
        desc_lines << "🔗 Planner: #{base_url.chomp('/')}/meal_plans"
      end
    end

    desc_lines.join("\n")
  end

  def build_url(slot)
    return nil if base_url.blank?

    if slot.recipe
      "#{base_url.chomp('/')}/recipes/#{slot.recipe.to_param}"
    else
      "#{base_url.chomp('/')}/meal_plans"
    end
  end

  def escape_text(text)
    return "" if text.blank?

    text.to_s
        .gsub("\\") { "\\\\" }
        .gsub(";") { "\\;" }
        .gsub(",") { "\\," }
        .gsub("\r\n", "\\n")
        .gsub("\n", "\\n")
        .gsub("\r", "")
  end

  def fold_lines(lines)
    lines.flat_map do |line|
      fold_single_line(line)
    end
  end

  private

  def scoped_slots
    query = household.meal_plan_slots
                     .includes(:family_member, recipe: :recipe_ingredients)
                     .where(date: (Date.current - 14.days)..(Date.current + 35.days))
                     .order(:date, :meal_type)

    query = query.where(family_member_id: member.id) if member

    query
  end

  def fold_single_line(line)
    return [ line ] if line.bytesize <= 75

    result = []
    current_line = +""
    current_bytes = 0
    max_bytes = 75

    line.each_char do |char|
      char_bytes = char.bytesize
      if current_bytes + char_bytes > max_bytes
        result << current_line
        current_line = +" " << char
        current_bytes = 1 + char_bytes
      else
        current_line << char
        current_bytes += char_bytes
      end
    end
    result << current_line unless current_line.empty?
    result
  end
end
