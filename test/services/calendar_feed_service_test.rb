require "test_helper"

class CalendarFeedServiceTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
    @member = family_members(:one)
    @member_two = family_members(:two)
    @meal_plan = @household.current_meal_plan(Date.current.beginning_of_week)

    @recipe = recipes(:one)
    @recipe.recipe_ingredients.create!(
      name: "Olive Oil",
      quantity: "2",
      unit: "tbsp"
    )

    # Clean existing slots for this week to have deterministic tests
    @meal_plan.meal_plan_slots.destroy_all

    @slot1 = @meal_plan.meal_plan_slots.create!(
      date: Date.current,
      meal_type: "dinner",
      recipe: @recipe,
      family_member: @member,
      notes: "Serve with warm bread, garlic & butter"
    )

    @slot2 = @meal_plan.meal_plan_slots.create!(
      date: Date.current + 1.day,
      meal_type: "lunch",
      custom_title: "Grilled Cheese",
      family_member: @member_two
    )

    @slot3 = @meal_plan.meal_plan_slots.create!(
      date: Date.current + 2.days,
      meal_type: "breakfast",
      custom_title: "No Meal Planned"
    )
  end

  test "generates RFC 5545 valid calendar structure" do
    service = CalendarFeedService.new(@household, base_url: "https://familyplates.example.com")
    ics = service.generate_ics

    assert_includes ics, "BEGIN:VCALENDAR\r\n"
    assert_includes ics, "VERSION:2.0\r\n"
    assert_includes ics, "PRODID:-//FamilyPlates//Meal Planner//EN\r\n"
    assert_includes ics, "CALSCALE:GREGORIAN\r\n"
    assert_includes ics, "METHOD:PUBLISH\r\n"
    assert_includes ics, "X-WR-CALNAME:FamilyPlates - #{@household.name}\r\n"
    assert_includes ics, "END:VCALENDAR\r\n"
  end

  test "generates VEVENT blocks for active slots and skips unassigned placeholders" do
    service = CalendarFeedService.new(@household, base_url: "https://familyplates.example.com")
    ics = service.generate_ics

    assert_includes ics, "UID:meal-plan-slot-#{@slot1.id}@familyplates"
    assert_includes ics, "UID:meal-plan-slot-#{@slot2.id}@familyplates"
    assert_not_includes ics, "UID:meal-plan-slot-#{@slot3.id}@familyplates"

    assert_includes ics, "SUMMARY:🍽️ Dinner: #{@recipe.title} (Cook: #{@member.name})"
    assert_includes ics, "SUMMARY:🍽️ Lunch: Grilled Cheese (Cook: #{@member_two.name})"
    assert_includes ics, "STATUS:CONFIRMED"
    assert_includes ics, "TRANSP:TRANSPARENT"
  end

  test "includes recipe details, ingredients preview, and links in description" do
    service = CalendarFeedService.new(@household, base_url: "https://familyplates.example.com")
    ics = service.generate_ics

    assert_includes ics, "👨‍🍳 Cook: #{@member.name}"
    assert_includes ics, "Olive Oil"
    assert_includes ics, "https://familyplates.example.com/recipes/#{@recipe.to_param}"
  end

  test "filters events by member when member is provided" do
    service = CalendarFeedService.new(@household, member: @member, base_url: "https://familyplates.example.com")
    ics = service.generate_ics

    assert_includes ics, "X-WR-CALNAME:FamilyPlates - #{@member.name}'s Cooking\r\n"
    assert_includes ics, "UID:meal-plan-slot-#{@slot1.id}@familyplates"
    assert_not_includes ics, "UID:meal-plan-slot-#{@slot2.id}@familyplates"
  end

  test "escapes special characters for RFC 5545 compliance" do
    service = CalendarFeedService.new(@household)
    raw = "Item 1, Item 2; with \\ backslash and\nnewline"
    escaped = service.escape_text(raw)

    assert_equal "Item 1\\, Item 2\\; with \\\\ backslash and\\nnewline", escaped
  end

  test "folds long lines to 75 octets" do
    service = CalendarFeedService.new(@household)
    long_line = "DESCRIPTION:" + ("A" * 120)
    folded = service.fold_lines([ long_line ])

    assert folded.size >= 2
    folded.each do |line|
      assert line.bytesize <= 75, "Line exceeded 75 bytes: #{line.bytesize}"
    end
    assert_equal " ", folded[1][0], "Folded line must start with whitespace"
  end

  test "calculates correct start and end times based on household preferences" do
    @household.update!(dinner_time: "18:30")
    service = CalendarFeedService.new(@household)

    start_time, end_time = service.calculate_slot_times(@slot1)

    assert_equal 18, start_time.hour
    assert_equal 30, start_time.min
    assert_equal 19, end_time.hour
    assert_equal 30, end_time.min
  end

  test "publishes meal times against the household's clock, not the server's" do
    @household.update!(dinner_time: "18:00", time_zone: "America/Chicago")
    service = CalendarFeedService.new(@household)

    start_time, = service.calculate_slot_times(@slot1)

    # Six in that kitchen, whatever the server's zone is - a UTC box was
    # publishing 18:00Z, which is mid-afternoon to a Chicago subscriber.
    assert_equal 18, start_time.hour
    assert_equal "America/Chicago", start_time.time_zone.name
    assert_includes service.generate_ics, "X-WR-TIMEZONE:America/Chicago"
  end
end
