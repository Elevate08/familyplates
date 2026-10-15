# How often a household shops and one day it shops. Existing households get
# weekly on Saturday (2026-01-03 is a Saturday).
class AddShoppingScheduleToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :shopping_frequency, :string, default: "weekly", null: false
    add_column :households, :shopping_anchor_on, :date, default: "2026-01-03", null: false
  end
end
