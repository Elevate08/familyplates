class AddGoogleCalendarAndMealTimesToHouseholdsAndSlots < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :google_calendar_id, :string
    add_column :households, :google_calendar_enabled, :boolean, default: false, null: false
    add_column :households, :breakfast_time, :string, default: "08:00", null: false
    add_column :households, :lunch_time, :string, default: "12:30", null: false
    add_column :households, :dinner_time, :string, default: "18:00", null: false

    add_column :meal_plan_slots, :google_event_id, :string
    add_index :meal_plan_slots, :google_event_id
  end
end
