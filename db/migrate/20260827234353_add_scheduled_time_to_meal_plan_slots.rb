class AddScheduledTimeToMealPlanSlots < ActiveRecord::Migration[8.1]
  def change
    add_column :meal_plan_slots, :scheduled_time, :string
  end
end
