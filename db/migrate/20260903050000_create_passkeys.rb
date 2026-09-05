class CreatePasskeys < ActiveRecord::Migration[8.1]
  def change
    create_table :passkeys, id: :string do |t|
      t.references :user, null: false, type: :string, foreign_key: { on_delete: :cascade }
      t.string :nickname
      t.string :external_id, null: false
      t.text :public_key, null: false
      t.integer :sign_count, default: 0, null: false
      t.datetime :last_used_at
      t.timestamps null: false
    end

    add_index :passkeys, :external_id, unique: true
    add_index :passkeys, %i[user_id created_at]
  end
end
