class AddCalendarFeedTokenToHouseholds < ActiveRecord::Migration[8.1]
  def change
    add_column :households, :calendar_feed_token, :string
    add_index :households, :calendar_feed_token, unique: true

    reversible do |dir|
      dir.up do
        Household.reset_column_information
        Household.unscoped.find_each do |household|
          household.update_column(:calendar_feed_token, SecureRandom.hex(16))
        end
      end
    end
  end
end
