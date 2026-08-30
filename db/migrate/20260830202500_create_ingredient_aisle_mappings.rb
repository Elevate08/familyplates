class CreateIngredientAisleMappings < ActiveRecord::Migration[8.0]
  def change
    create_table :ingredient_aisle_mappings do |t|
      t.references :household, foreign_key: true, null: true
      t.string :name, null: false
      t.string :aisle_category, null: false
      t.integer :count, default: 1, null: false

      t.timestamps
    end

    add_index :ingredient_aisle_mappings, [:household_id, :name]
    add_index :ingredient_aisle_mappings, [:name, :aisle_category]
  end
end
