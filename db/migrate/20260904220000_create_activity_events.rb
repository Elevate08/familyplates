class CreateActivityEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :activity_events, id: :string do |t|
      t.string :household_id, null: false
      t.string :actor_id
      t.string :event_type, null: false
      t.string :source, null: false, default: "web"
      t.string :target_type
      t.string :target_id
      t.json :metadata, null: false, default: {}
      t.timestamps
    end

    add_index :activity_events, :household_id
    add_index :activity_events, [ :household_id, :created_at ]
    add_index :activity_events, [ :target_type, :target_id ]
    add_foreign_key :activity_events, :households
    add_foreign_key :activity_events, :family_members, column: :actor_id
  end
end
