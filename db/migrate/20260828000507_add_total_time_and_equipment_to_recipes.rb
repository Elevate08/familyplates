class AddTotalTimeAndEquipmentToRecipes < ActiveRecord::Migration[8.1]
  def change
    add_column :recipes, :total_time, :integer
    add_column :recipes, :equipment, :string
  end
end
