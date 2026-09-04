class CreatePromotionPrograms < ActiveRecord::Migration[8.0]
  def change
    create_table :promotion_programs, id: :string do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.integer :discount_percent
      t.string :provider_promotion_code_id
      t.datetime :starts_at
      t.datetime :ends_at
      t.integer :max_redemptions
      t.integer :redeemed_count, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.text :notes
      t.timestamps
    end

    add_index :promotion_programs, :code, unique: true
    add_index :promotion_programs, :active
  end
end
