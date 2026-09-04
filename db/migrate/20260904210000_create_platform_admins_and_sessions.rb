class CreatePlatformAdminsAndSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :platform_admins, id: :string do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.string :otp_secret, null: false
      t.string :role, null: false, default: "owner"
      t.boolean :active, null: false, default: true
      t.datetime :last_signed_in_at
      t.timestamps
    end
    add_index :platform_admins, :email, unique: true

    create_table :platform_admin_sessions, id: :string do |t|
      t.string :token, null: false
      t.string :platform_admin_id, null: false
      t.string :ip_address
      t.string :user_agent
      t.datetime :last_active_at, null: false
      t.timestamps
    end
    add_index :platform_admin_sessions, :token, unique: true
    add_index :platform_admin_sessions, :platform_admin_id
    add_foreign_key :platform_admin_sessions, :platform_admins
  end
end
