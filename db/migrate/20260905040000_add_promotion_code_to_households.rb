class AddPromotionCodeToHouseholds < ActiveRecord::Migration[8.0]
  def change
    add_column :households, :promotion_code, :string
    add_index :households, :promotion_code
  end
end
