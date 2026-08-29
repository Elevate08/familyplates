class RemoveUsersAndSessions < ActiveRecord::Migration[8.1]
  def change
    drop_table :sessions, if_exists: true
    drop_table :users, if_exists: true
  end
end
