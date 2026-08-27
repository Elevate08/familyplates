class AddGoogleServiceAccountJsonToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :google_service_account_json, :text
  end
end
