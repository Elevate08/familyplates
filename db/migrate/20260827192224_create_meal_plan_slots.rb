class CreateMealPlanSlots < ActiveRecord::Migration[8.1]
  def change
    create_table :meal_plan_slots do |t|
      t.references :meal_plan, null: false, foreign_key: true
      t.date :date, null: false
      t.string :meal_type, default: "dinner", null: false
      t.references :recipe, null: true, foreign_key: true
      t.references :family_member, null: true, foreign_key: true
      t.string :custom_title
      t.text :notes

      t.timestamps
    end
    add_index :meal_plan_slots, [:meal_plan_id, :date, :meal_type]
  end
end
