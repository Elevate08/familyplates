class AddMealTypesToRecipes < ActiveRecord::Migration[8.1]
  def change
    add_column :recipes, :meal_types, :string, default: "breakfast,lunch,dinner"
  end
end
