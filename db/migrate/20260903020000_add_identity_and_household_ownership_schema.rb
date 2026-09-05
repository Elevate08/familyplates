require "securerandom"

class AddIdentityAndHouseholdOwnershipSchema < ActiveRecord::Migration[8.1]
  def up
    create_users
    create_identities
    create_sessions
    add_household_ownership
  end

  def down
    remove_index :family_members, %i[household_id user_id]
    remove_reference :family_members, :user, foreign_key: true
    remove_index :households, :join_code
    remove_columns :households, :join_code, :onboarded_at
    drop_table :sessions
    drop_table :identities
    drop_table :users
  end

  private

  def create_users
    create_table :users, id: :string do |t|
      t.string :email, null: false, collation: "NOCASE"
      t.string :password_digest
      t.datetime :verified_at
      t.timestamps null: false
    end
    add_index :users, :email, unique: true
  end

  def create_identities
    create_table :identities, id: :string do |t|
      t.references :user, null: false, type: :string, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :uid, null: false
      t.timestamps null: false
    end
    add_index :identities, %i[provider uid], unique: true
  end

  def create_sessions
    create_table :sessions, id: :string do |t|
      t.references :user, null: false, type: :string, foreign_key: { on_delete: :cascade }
      t.string :token, null: false
      t.string :kind, null: false, default: "browser"
      t.string :user_agent
      t.string :ip_address
      t.datetime :last_active_at, null: false
      t.datetime :expires_at
      t.timestamps null: false
    end
    add_index :sessions, :token, unique: true
  end

  def add_household_ownership
    add_column :households, :join_code, :string
    add_column :households, :onboarded_at, :datetime

    suppress_messages { backfill_household_ownership }

    change_column_null :households, :join_code, false
    add_index :households, :join_code, unique: true
    add_reference :family_members, :user, type: :string, foreign_key: { on_delete: :nullify }, index: false
    add_index :family_members, %i[household_id user_id], unique: true, where: "user_id IS NOT NULL"
  end

  def backfill_household_ownership
    used_codes = []

    connection.select_rows("SELECT id, created_at FROM households").each do |id, created_at|
      join_code = generate_join_code(used_codes)
      used_codes << join_code
      execute <<~SQL.squish
        UPDATE households
        SET join_code = #{connection.quote(join_code)},
            onboarded_at = #{connection.quote(created_at)}
        WHERE id = #{connection.quote(id)}
      SQL
    end
  end

  def generate_join_code(used_codes)
    loop do
      code = SecureRandom.alphanumeric(12).upcase.scan(/.{4}/).join("-")
      return code unless used_codes.include?(code)
    end
  end
end
