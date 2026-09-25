class CreateAccountDeletionRequests < ActiveRecord::Migration[8.0]
  def change
    create_table :account_deletion_requests, id: :string do |t|
      t.references :household, null: false, foreign_key: true, type: :string
      t.references :requested_by_user, null: true, foreign_key: { to_table: :users }, type: :string
      t.string :status, null: false, default: "pending"
      t.datetime :requested_at, null: false
      t.datetime :resolved_at
      t.references :resolved_by_platform_admin, null: true, foreign_key: { to_table: :platform_admins }, type: :string
      t.text :resolution_note
      t.timestamps
    end

    add_index :account_deletion_requests, [ :household_id, :status ]
  end
end
