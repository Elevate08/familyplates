class AddFulfilledAtToRecipeRequests < ActiveRecord::Migration[8.1]
  def change
    add_column :recipe_requests, :fulfilled_at, :datetime
    add_index :recipe_requests, [:recipe_id, :family_member_id, :fulfilled_at], name: "index_recipe_requests_on_active_request"
  end
end
