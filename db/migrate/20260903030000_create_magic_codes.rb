class CreateMagicCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :magic_codes, id: :string do |t|
      t.references :user, null: true, type: :string, foreign_key: { on_delete: :cascade }
      t.string :email, null: false, collation: "NOCASE"
      t.string :code, null: false
      t.datetime :expires_at, null: false
      t.timestamps null: false
    end

    add_index :magic_codes, :code, unique: true
    add_index :magic_codes, :email
  end
end
