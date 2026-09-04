class CreateSupportThreadsAndMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :support_threads, id: :string do |t|
      t.string :household_id, null: false
      t.string :created_by_user_id
      t.string :subject, null: false
      t.string :status, null: false, default: "open"
      t.datetime :last_message_at
      t.datetime :resolved_at
      t.timestamps
    end

    create_table :support_messages, id: :string do |t|
      t.string :support_thread_id, null: false
      t.string :user_id
      t.string :platform_admin_id
      t.text :body, null: false
      t.timestamps
    end

    add_index :support_threads, [ :household_id, :status ]
    add_index :support_threads, [ :household_id, :last_message_at ]
    add_index :support_messages, [ :support_thread_id, :created_at ]
    add_foreign_key :support_threads, :households
    add_foreign_key :support_threads, :users, column: :created_by_user_id
    add_foreign_key :support_messages, :support_threads
    add_foreign_key :support_messages, :users
    add_foreign_key :support_messages, :platform_admins
  end
end
