require "test_helper"
require "tmpdir"

class IdentityAndHouseholdOwnershipMigrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  class LegacyRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  test "migration creates UUID primary keys" do
    with_legacy_database do |connection|
      migrate(connection, :up)

      assert_equal({ "users" => "id", "identities" => "id", "sessions" => "id" }, primary_keys(connection))
    end
  end

  test "migration creates the required columns and nullability" do
    with_legacy_database do |connection|
      migrate(connection, :up)

      assert_equal expected_column_signatures, column_signatures(connection)
    end
  end

  test "migration makes email case insensitive" do
    with_legacy_database do |connection|
      migrate(connection, :up)

      assert_equal "NOCASE", connection.columns(:users).find { |column| column.name == "email" }.collation
    end
  end

  test "migration creates the required indexes" do
    with_legacy_database do |connection|
      migrate(connection, :up)

      assert_equal expected_indexes, indexes(connection)
    end
  end

  test "migration creates the required delete behavior" do
    with_legacy_database do |connection|
      migrate(connection, :up)

      assert_equal expected_foreign_keys, foreign_keys(connection)
    end
  end

  test "migration backfills existing household ownership" do
    with_legacy_database do |connection|
      migrate(connection, :up)

      household = connection.select_one("SELECT * FROM households WHERE id = 'household-1'")
      assert_equal household["created_at"], household["onboarded_at"]
      assert_match(/\A[A-Z0-9]{4}(?:-[A-Z0-9]{4}){2}\z/, household["join_code"])
    end
  end

  test "rollback removes every schema addition" do
    with_legacy_database do |connection|
      migrate(connection, :up)

      migrate(connection, :down)

      assert_equal %w[family_members households], connection.tables.sort
      assert_equal %w[created_at id name updated_at], connection.columns(:households).map(&:name).sort
      assert_equal %w[created_at household_id id name updated_at], connection.columns(:family_members).map(&:name).sort
    end
  end

  test "rollback preserves records and the original household relationship" do
    with_legacy_database do |connection|
      migrate(connection, :up)
      migrate(connection, :down)

      assert_equal "Kitchen", connection.select_value("SELECT name FROM households WHERE id = 'household-1'")
      assert_equal "Alex", connection.select_value("SELECT name FROM family_members WHERE id = 'member-1'")
      assert_equal [ [ "family_members", "households", "household_id", nil ] ], foreign_keys(connection)
      assert_empty connection.execute("PRAGMA foreign_key_check")
    end
  end

  private

  def with_legacy_database
    Dir.mktmpdir("familyplates-identity-schema-test") do |directory|
      LegacyRecord.establish_connection adapter: "sqlite3", database: File.join(directory, "legacy.sqlite3")

      LegacyRecord.connection_pool.with_connection do |connection|
        build_legacy_schema(connection)
        seed_legacy_records(connection)
        yield connection
      end
    ensure
      LegacyRecord.connection_pool.disconnect!
    end
  end

  def migrate(connection, direction)
    require Rails.root.join("db/migrate/20260903020000_add_identity_and_household_ownership_schema")
    migration = AddIdentityAndHouseholdOwnershipSchema.new
    migration.verbose = false
    migration.exec_migration(connection, direction)
  end

  def build_legacy_schema(connection)
    connection.create_table :households, id: :string do |t|
      t.string :name, null: false
      t.timestamps null: false
    end
    connection.create_table :family_members, id: :string do |t|
      t.string :household_id, null: false
      t.string :name, null: false
      t.timestamps null: false
    end
    connection.add_index :family_members, :household_id
    connection.add_foreign_key :family_members, :households
  end

  def seed_legacy_records(connection)
    connection.execute <<~SQL
      INSERT INTO households (id, name, created_at, updated_at)
      VALUES ('household-1', 'Kitchen', '2026-09-01 12:00:00', '2026-09-01 12:00:00')
    SQL
    connection.execute <<~SQL
      INSERT INTO family_members (id, household_id, name, created_at, updated_at)
      VALUES ('member-1', 'household-1', 'Alex', '2026-09-01 12:00:00', '2026-09-01 12:00:00')
    SQL
  end

  def expected_column_signatures
    {
      users: {
        id: [ :string, false ], email: [ :string, false ], password_digest: [ :string, true ],
        verified_at: [ :datetime, true ], created_at: [ :datetime, false ], updated_at: [ :datetime, false ]
      },
      identities: {
        id: [ :string, false ], user_id: [ :string, false ], provider: [ :string, false ],
        uid: [ :string, false ], created_at: [ :datetime, false ], updated_at: [ :datetime, false ]
      },
      sessions: {
        id: [ :string, false ], user_id: [ :string, false ], token: [ :string, false ],
        kind: [ :string, false ], user_agent: [ :string, true ], ip_address: [ :string, true ],
        last_active_at: [ :datetime, false ], expires_at: [ :datetime, true ],
        created_at: [ :datetime, false ], updated_at: [ :datetime, false ]
      },
      households: { join_code: [ :string, false ], onboarded_at: [ :datetime, true ] },
      family_members: { user_id: [ :string, true ] }
    }
  end

  def primary_keys(connection)
    %w[users identities sessions].to_h { |table| [ table, connection.primary_key(table) ] }
  end

  def column_signatures(connection)
    expected_column_signatures.to_h do |table, expected_columns|
      actual_columns = connection.columns(table).to_h { |column| [ column.name.to_sym, [ column.type, column.null ] ] }
      [ table, actual_columns.slice(*expected_columns.keys) ]
    end
  end

  def expected_indexes
    [
      [ "family_members", %w[household_id], false, nil ],
      [ "family_members", %w[household_id user_id], true, "user_id IS NOT NULL" ],
      [ "households", %w[join_code], true, nil ],
      [ "identities", %w[provider uid], true, nil ],
      [ "identities", %w[user_id], false, nil ],
      [ "sessions", %w[token], true, nil ],
      [ "sessions", %w[user_id], false, nil ],
      [ "users", %w[email], true, nil ]
    ]
  end

  def indexes(connection)
    expected_indexes.map(&:first).uniq.flat_map do |table|
      connection.indexes(table).map { |index| [ table, index.columns, index.unique, index.where ] }
    end.sort
  end

  def expected_foreign_keys
    [
      [ "family_members", "households", "household_id", nil ],
      [ "family_members", "users", "user_id", :nullify ],
      [ "identities", "users", "user_id", :cascade ],
      [ "sessions", "users", "user_id", :cascade ]
    ]
  end

  def foreign_keys(connection)
    expected_foreign_keys.map(&:first).uniq.flat_map do |table|
      connection.foreign_keys(table).map { |key| [ table, key.to_table, key.column, key.on_delete ] }
    end.sort
  end
end
