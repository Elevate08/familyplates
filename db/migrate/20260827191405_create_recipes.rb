class CreateRecipes < ActiveRecord::Migration[8.1]
  def change
    create_table :recipes do |t|
      t.references :household, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.integer :prep_time, default: 15
      t.integer :cook_time, default: 20
      t.integer :servings, default: 4
      t.string :source_url
      t.string :image_url
      t.text :instructions
      t.string :tags

      t.timestamps
    end
    add_index :recipes, [:household_id, :title]
  end
end
