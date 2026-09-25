class RemoveGoogleCalendarDirectSync < ActiveRecord::Migration[8.1]
  def change
    remove_column :households, :google_calendar_enabled, :boolean, default: false, null: false
    remove_column :households, :google_calendar_id, :string
    remove_column :households, :google_service_account_json, :text
    remove_column :meal_plan_slots, :google_event_id, :string
  end
end
