class SyncMealPlanSlotJob < ApplicationJob
  queue_as :default

  def perform(slot_id, action = "upsert", event_id = nil, household_id = nil)
    slot = slot_id.present? ? MealPlanSlot.find_by(id: slot_id) : nil
    household = slot&.meal_plan&.household || (household_id.present? ? Household.find_by(id: household_id) : nil)
    return unless household&.google_calendar_enabled? && household&.google_calendar_id.present?

    service = GoogleCalendarService.new(household)
    target_event_id = event_id || slot&.google_event_id

    if action == "delete" || (slot && slot.display_title == "No Meal Planned")
      if target_event_id.present?
        service.delete_event_by_id(target_event_id)
        slot&.update_column(:google_event_id, nil)
      end
    elsif slot && slot.display_title != "No Meal Planned"
      service.create_or_update_event(slot)
    end
  end
end
