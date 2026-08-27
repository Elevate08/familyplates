class CreateRecipeIngredients < ActiveRecord::Migration[8.1]
  def change
    create_table :recipe_ingredients do |t|
      t.references :recipe, null: false, foreign_key: true
      t.string :raw_text
      t.string :name, null: false
      t.decimal :quantity
      t.string :unit
      t.string :aisle_category, default: "Other", null: false

      t.timestamps
    end
    add_index :recipe_ingredients, [:recipe_id, :name]
  end
end
