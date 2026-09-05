class CreateDeviceGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :device_grants, id: :string do |t|
      t.string :device_code, null: false
      t.string :user_code, null: false
      t.references :household, null: true, type: :string, foreign_key: { on_delete: :cascade }
      t.references :user, null: true, type: :string, foreign_key: { on_delete: :cascade }
      t.references :session, null: true, type: :string, foreign_key: { on_delete: :cascade }
      t.string :kind, default: "kiosk", null: false
      t.string :status, default: "pending", null: false
      t.string :client_name
      t.string :user_agent
      t.string :ip_address
      t.datetime :last_polled_at
      t.datetime :expires_at, null: false
      t.datetime :approved_at
      t.timestamps null: false
    end

    add_index :device_grants, :device_code, unique: true
    add_index :device_grants, :user_code, unique: true
    add_index :device_grants, :status
  end
end
