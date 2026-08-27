require "test_helper"

class SyncMealPlanSlotJobTest < ActiveJob::TestCase
  setup do
    @household = households(:one)
    @household.update!(
      google_calendar_id: "family-meals@group.calendar.google.com",
      google_calendar_enabled: true
    )
    @slot = meal_plan_slots(:one)
    @slot.update_column(:google_event_id, "gcal_job_123")
  end

  test "perform delete calls delete_event_by_id on GoogleCalendarService" do
    deleted_ids = []
    original_delete = GoogleCalendarService.instance_method(:delete_event_by_id)
    GoogleCalendarService.define_method(:delete_event_by_id) { |id| deleted_ids << id }

    begin
      SyncMealPlanSlotJob.perform_now(nil, "delete", "gcal_job_123", @household.id)
      assert_includes deleted_ids, "gcal_job_123"
    ensure
      GoogleCalendarService.define_method(:delete_event_by_id, original_delete)
    end
  end

  test "perform upsert calls create_or_update_event on GoogleCalendarService" do
    upserted_slots = []
    original_upsert = GoogleCalendarService.instance_method(:create_or_update_event)
    GoogleCalendarService.define_method(:create_or_update_event) { |slot| upserted_slots << slot.id }

    begin
      SyncMealPlanSlotJob.perform_now(@slot.id, "upsert")
      assert_includes upserted_slots, @slot.id
    ensure
      GoogleCalendarService.define_method(:create_or_update_event, original_upsert)
    end
  end
end
