class AddNumberToRecipesAndMealPlans < ActiveRecord::Migration[8.0]
  def change
    add_column :recipes, :number, :integer
    add_column :meal_plans, :number, :integer

    reversible do |dir|
      dir.up do
        # Backfill sequential number for recipes per household
        execute <<~SQL
          UPDATE recipes
          SET number = (
            SELECT COUNT(*)
            FROM recipes AS r2
            WHERE r2.household_id = recipes.household_id
              AND (r2.created_at < recipes.created_at OR (r2.created_at = recipes.created_at AND r2.id <= recipes.id))
          )
        SQL

        # Backfill sequential number for meal_plans per household
        execute <<~SQL
          UPDATE meal_plans
          SET number = (
            SELECT COUNT(*)
            FROM meal_plans AS mp2
            WHERE mp2.household_id = meal_plans.household_id
              AND (mp2.created_at < meal_plans.created_at OR (mp2.created_at = meal_plans.created_at AND mp2.id <= meal_plans.id))
          )
        SQL
      end
    end

    add_index :recipes, [ :household_id, :number ], unique: true
    add_index :meal_plans, [ :household_id, :number ], unique: true
  end
end
