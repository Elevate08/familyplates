class CreateHouseholds < ActiveRecord::Migration[8.1]
  def change
    create_table :households do |t|
      t.string :name, null: false
      t.string :calendar_token, null: false

      t.timestamps
    end
    add_index :households, :calendar_token, unique: true
  end
end
