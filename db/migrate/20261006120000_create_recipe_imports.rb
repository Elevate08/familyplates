class CreateRecipeImports < ActiveRecord::Migration[8.1]
  # One row per recipe import: who asked, for which web address, how far the
  # background job has got, and what it found (the scraped recipe as JSON) or
  # why it failed, and the recipe the job saved from it. The waiting page reads this row. Rows are throwaway and are
  # deleted a day after they were made (config/recurring.yml).
  def change
    create_table :recipe_imports, id: :string do |t|
      t.string :household_id, null: false
      t.string :family_member_id
      t.string :url, null: false
      t.string :status, null: false, default: "queued"
      t.string :error
      t.json :data
      t.integer :recipe_id
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :recipe_imports, :household_id
    add_index :recipe_imports, :created_at
    add_foreign_key :recipe_imports, :households
    add_foreign_key :recipe_imports, :family_members
  end
end
