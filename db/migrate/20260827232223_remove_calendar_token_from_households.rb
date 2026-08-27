class RemoveCalendarTokenFromHouseholds < ActiveRecord::Migration[8.1]
  def change
    remove_column :households, :calendar_token, :string
  end
end
