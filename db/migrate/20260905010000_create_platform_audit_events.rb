class CreatePlatformAuditEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :platform_audit_events, id: :string do |t|
      t.references :platform_admin, null: true, foreign_key: { to_table: :platform_admins }, type: :string
      t.string :action, null: false
      t.string :target_type
      t.string :target_id
      t.json :metadata, null: false, default: {}
      t.string :ip_address
      t.text :user_agent
      t.timestamps
    end

    add_index :platform_audit_events, [ :target_type, :target_id ]
    add_index :platform_audit_events, :action
    add_index :platform_audit_events, :created_at
  end
end
