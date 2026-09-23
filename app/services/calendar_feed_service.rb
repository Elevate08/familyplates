# RFC 5545 feed. Times are UTC from the household zone and meal preferences.
# Lines fold at 75 octets. Events are TRANSPARENT so they do not block the calendar.
class CalendarFeedService
  CRLF = "\r\n".freeze
  MEAL_DURATIONS = { "breakfast" => 45, "lunch" => 45, "dinner" => 60 }.freeze

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
      next unless slot.planned?

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
    start_time = slot.scheduled_at
    end_time = start_time + MEAL_DURATIONS.fetch(slot.meal_type, MEAL_DURATIONS.fetch("dinner")).minutes

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
      details = [
        ("Prep: #{r.prep_time}m" if r.prep_time),
        ("Cook: #{r.cook_time}m" if r.cook_time),
        ("Servings: #{r.servings}" if r.servings)
      ].compact
      desc_lines << "⏱️ #{details.join(' | ')}" if details.any?
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
      label = slot.recipe ? "Recipe" : "Planner"
      desc_lines << "🔗 #{label}: #{build_url(slot)}"
    end

    desc_lines.join("\n")
  end

  def build_url(slot)
    return nil if base_url.blank?

    path = slot.recipe ? "/recipes/#{slot.recipe.to_param}" : "/meal_plans"
    "#{base_url.chomp('/')}#{path}"
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
                     .includes(:family_member, { meal_plan: :household }, recipe: :recipe_ingredients)
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
