class IcalGenerator
  attr_reader :household

  def self.call(household)
    new(household).generate
  end

  def initialize(household)
    @household = household
  end

  def generate
    lines = []
    lines << "BEGIN:VCALENDAR"
    lines << "VERSION:2.0"
    lines << "PRODID:-//FamilyPlates//Family Meal Planner//EN"
    lines << "CALSCALE:GREGORIAN"
    lines << "METHOD:PUBLISH"
    lines << "X-WR-CALNAME:#{escape_ical_text(household.name)} - Meal Plan"
    lines << "X-WR-CALDESC:Weekly dinner and lunch menu for #{escape_ical_text(household.name)}"

    # Generate events for all meal plan slots in the last 2 weeks and next 4 weeks
    start_window = Date.current.beginning_of_week - 14.days
    end_window = Date.current.beginning_of_week + 28.days

    slots = MealPlanSlot.joins(:meal_plan)
                        .where(meal_plans: { household_id: household.id })
                        .where("meal_plan_slots.date >= ? AND meal_plan_slots.date <= ?", start_window, end_window)
                        .includes(:recipe, :family_member)

    slots.each do |slot|
      next if slot.display_title == "No Meal Planned"

      lines.concat(build_vevent(slot))
    end

    lines << "END:VCALENDAR"
    lines.join("\r\n") + "\r\n"
  end

  private

  def build_vevent(slot)
    dt_stamp = Time.current.utc.strftime("%Y%m%dT%H%M%SZ")
    dt_start = slot.date.strftime("%Y%m%d")
    dt_end = (slot.date + 1.day).strftime("%Y%m%d")
    uid = "mealhub-slot-#{slot.id}-#{slot.date}@mealhub"

    meal_type_tag = slot.meal_type.capitalize
    cook_tag = slot.family_member ? " (Cook: #{slot.family_member.name})" : ""
    summary = "🍽️ [#{meal_type_tag}] #{slot.display_title}#{cook_tag}"

    desc_parts = []
    desc_parts << "Meal: #{slot.display_title}"
    desc_parts << "Chef: #{slot.family_member.name}" if slot.family_member
    desc_parts << "Notes: #{slot.notes}" if slot.notes.present?
    desc_parts << "Prep Time: #{slot.recipe.prep_time}m | Cook Time: #{slot.recipe.cook_time}m" if slot.recipe

    description = escape_ical_text(desc_parts.join("\n"))

    event = []
    event << "BEGIN:VEVENT"
    event << "UID:#{uid}"
    event << "DTSTAMP:#{dt_stamp}"
    event << "DTSTART;VALUE=DATE:#{dt_start}"
    event << "DTEND;VALUE=DATE:#{dt_end}"
    event << "SUMMARY:#{escape_ical_text(summary)}"
    event << "DESCRIPTION:#{description}"
    event << "TRANSP:TRANSPARENT"
    event << "END:VEVENT"
    event
  end

  def escape_ical_text(text)
    text.to_s.gsub("\\", "\\\\").gsub(";", "\\;").gsub(",", "\\,").gsub("\n", "\\n")
  end
end
