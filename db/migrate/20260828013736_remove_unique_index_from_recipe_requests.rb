class RemoveUniqueIndexFromRecipeRequests < ActiveRecord::Migration[8.1]
  def change
    remove_index :recipe_requests, name: "index_recipe_requests_unique_per_week"
    add_index :recipe_requests, [ :recipe_id, :family_member_id, :week_start_date ]
  end
end
