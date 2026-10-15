class CreateNoticeDeliveries < ActiveRecord::Migration[8.1]
  # One row per reminder sent about one event: which household, what kind,
  # the instant the event happens (a trial's end), and how far ahead. The
  # unique index is what stops a reminder going out twice. A new event
  # instant (a trial extended) is a new event with its own reminders.
  def change
    create_table :notice_deliveries, id: :string do |t|
      t.string :household_id, null: false
      t.string :kind, null: false
      t.datetime :event_at, null: false
      t.string :threshold, null: false
      t.datetime :sent_at
      t.timestamps
    end
    add_index :notice_deliveries, %i[household_id kind event_at threshold], unique: true,
      name: "index_notice_deliveries_once_per_event"
  end
end
