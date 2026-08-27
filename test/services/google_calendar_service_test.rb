require "test_helper"

class GoogleCalendarServiceTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
    @household.update!(
      google_calendar_id: "family-meals@group.calendar.google.com",
      google_calendar_enabled: true,
      google_service_account_json: { "client_email" => "test@test.iam.gserviceaccount.com" }.to_json,
      breakfast_time: "07:30",
      lunch_time: "12:00",
      dinner_time: "17:30"
    )
    @plan = meal_plans(:one)
    @slot = meal_plan_slots(:one) # dinner
    @service = GoogleCalendarService.new(@household)
  end

  test "calculates start and end time based on meal type and household settings" do
    start_time, end_time = @service.calculate_slot_times(@slot)
    
    # Date is slot.date, time is 17:30 (dinner_time)
    assert_equal 17, start_time.hour
    assert_equal 30, start_time.min
    assert_equal 18, end_time.hour
    assert_equal 30, end_time.min # 60 min duration for dinner
  end

  test "builds correct event summary and description" do
    event_data = @service.build_event_data(@slot)

    assert_includes event_data[:summary], "Dinner:"
    assert_includes event_data[:summary], @slot.display_title
    assert_includes event_data[:description], "Cook:"
  end

  test "extracts service account email when configured via ENV" do
    orig = ENV["GOOGLE_CALENDAR_SERVICE_ACCOUNT_JSON"]
    ENV["GOOGLE_CALENDAR_SERVICE_ACCOUNT_JSON"] = { "client_email" => "familyplates-sync@test-project.iam.gserviceaccount.com" }.to_json

    assert_equal "familyplates-sync@test-project.iam.gserviceaccount.com", GoogleCalendarService.service_account_email
    assert GoogleCalendarService.configured?
  ensure
    ENV["GOOGLE_CALENDAR_SERVICE_ACCOUNT_JSON"] = orig
  end

  test "delete_event clears google_event_id column" do
    @slot.update_column(:google_event_id, "gcal_event_123")
    assert_equal "gcal_event_123", @slot.google_event_id

    # Mock delete_event_by_id
    deleted_ids = []
    @service.define_singleton_method(:delete_event_by_id) { |id| deleted_ids << id }

    @service.delete_event(@slot)
    assert_includes deleted_ids, "gcal_event_123"
    assert_nil @slot.reload.google_event_id
  end

  test "sync_meal_plan deletes events for cleared slots with google_event_id" do
    cleared_slot = @plan.meal_plan_slots.create!(
      date: @plan.week_start_date + 1.day,
      meal_type: "breakfast",
      custom_title: nil,
      recipe: nil,
      google_event_id: "gcal_cleared_456"
    )

    deleted_slots = []
    @service.define_singleton_method(:delete_event) { |slot| deleted_slots << slot.id }
    @service.define_singleton_method(:create_or_update_event) { |slot| }

    count = @service.sync_meal_plan(@plan)
    assert_includes deleted_slots, cleared_slot.id
  end
end
