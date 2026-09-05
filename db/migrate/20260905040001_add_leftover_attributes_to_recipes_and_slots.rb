class AddLeftoverAttributesToRecipesAndSlots < ActiveRecord::Migration[8.1]
  def change
    add_column :recipes, :leftover_capacity, :integer, default: 1, null: false
    add_column :recipes, :leftover_shelf_life_days, :integer, default: 3, null: false

    add_reference :meal_plan_slots, :leftover_source_slot, foreign_key: { to_table: :meal_plan_slots, on_delete: :nullify }, index: true, null: true
  end
end
