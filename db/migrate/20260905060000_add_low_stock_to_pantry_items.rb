class AddLowStockToPantryItems < ActiveRecord::Migration[8.1]
  # A timestamp rather than a boolean: "running low since Tuesday" is worth
  # knowing, and null already reads as "stocked". Nothing needs backfilling -
  # every existing item is, by definition, not flagged low.
  def change
    add_column :pantry_items, :low_stock_at, :datetime
    add_index :pantry_items, [ :household_id, :low_stock_at ]
  end
end
