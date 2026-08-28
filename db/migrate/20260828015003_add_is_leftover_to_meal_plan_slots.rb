class AddIsLeftoverToMealPlanSlots < ActiveRecord::Migration[8.1]
  def change
    add_column :meal_plan_slots, :is_leftover, :boolean, default: false, null: false
  end
end
