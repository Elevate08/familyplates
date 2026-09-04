class AddSuspensionToHouseholds < ActiveRecord::Migration[8.0]
  def change
    add_column :households, :suspended_at, :datetime
    add_column :households, :suspension_reason, :string
    add_index :households, :suspended_at
  end
end
