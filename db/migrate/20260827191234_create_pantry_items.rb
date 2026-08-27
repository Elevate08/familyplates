class CreatePantryItems < ActiveRecord::Migration[8.1]
  def change
    create_table :pantry_items do |t|
      t.references :household, null: false, foreign_key: true
      t.string :name, null: false
      t.string :aisle_category, default: "Pantry & Grains", null: false
      t.boolean :is_staple, default: true, null: false

      t.timestamps
    end
    add_index :pantry_items, [:household_id, :name], unique: true
  end
end
