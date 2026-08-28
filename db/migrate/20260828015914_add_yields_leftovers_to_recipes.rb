class AddYieldsLeftoversToRecipes < ActiveRecord::Migration[8.1]
  def change
    add_column :recipes, :yields_leftovers, :boolean, default: false, null: false
  end
end
