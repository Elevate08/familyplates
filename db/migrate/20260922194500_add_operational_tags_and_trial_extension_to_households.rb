class AddOperationalTagsAndTrialExtensionToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :operational_tags, :string, default: "", null: false
    add_column :households, :trial_extended_until, :datetime
  end
end
