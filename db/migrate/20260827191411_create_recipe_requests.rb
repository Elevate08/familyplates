class CreateRecipeRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :recipe_requests do |t|
      t.references :recipe, null: false, foreign_key: true
      t.references :family_member, null: false, foreign_key: true
      t.date :week_start_date, null: false

      t.timestamps
    end
    add_index :recipe_requests, [:recipe_id, :family_member_id, :week_start_date], unique: true, name: "index_recipe_requests_unique_per_week"
  end
end
