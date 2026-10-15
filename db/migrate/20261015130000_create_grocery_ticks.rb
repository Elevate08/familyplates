class CreateGroceryTicks < ActiveRecord::Migration[8.1]
  # One row per ticked (or un-ticked) grocery item on a list. A list is an exact
  # date range, so the same range on any of the household's devices shows the
  # same ticks. changed_at is the client's clock for the change (clamped to now
  # by the server); the newest change wins. Throwaway shopping state: it is not
  # part of the household export.
  def change
    create_table :grocery_ticks do |t|
      t.string :household_id, null: false
      t.date :list_from, null: false
      t.date :list_to, null: false
      t.string :item_key, null: false
      t.boolean :checked, null: false
      t.datetime :changed_at, null: false
      t.string :family_member_id
      t.timestamps
    end
    add_index :grocery_ticks, %i[household_id list_from list_to item_key], unique: true, name: "index_grocery_ticks_on_list_and_item"
    add_index :grocery_ticks, :family_member_id
    add_foreign_key :grocery_ticks, :households
    add_foreign_key :grocery_ticks, :family_members, on_delete: :nullify
  end
end
