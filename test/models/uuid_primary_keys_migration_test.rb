require "test_helper"
require "tmpdir"

class UuidPrimaryKeysMigrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  class LegacyRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  test "migration converts both primary keys and all seven foreign keys without breaking relationships" do
    with_legacy_database do |connection|
      migrate(connection, :up)

      assert_equal expected_uuid_columns, column_types(connection)
      assert_equal expected_foreign_keys, foreign_keys(connection)
      assert_equal expected_indexes, affected_indexes(connection)
      assert_preserved_relationships connection, id_pattern: UUID_PATTERN
    end
  end

  test "rollback restores integer keys without breaking relationships or autoincrement" do
    with_legacy_database do |connection|
      migrate(connection, :up)
      migrate(connection, :down)

      assert_equal expected_integer_columns, column_types(connection)
      assert_equal expected_foreign_keys, foreign_keys(connection)
      assert_equal expected_indexes, affected_indexes(connection)
      assert_preserved_relationships connection, id_pattern: /\A\d+\z/

      connection.execute <<~SQL
        INSERT INTO households (name, created_at, updated_at)
        VALUES ('Second household', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
      SQL
      assert_operator connection.select_value("SELECT MAX(id) FROM households"), :>, 1
    end
  end

  private

  def with_legacy_database
    Dir.mktmpdir("familyplates-uuid-migration-test") do |directory|
      LegacyRecord.establish_connection adapter: "sqlite3", database: File.join(directory, "legacy.sqlite3")

      LegacyRecord.connection_pool.with_connection do |connection|
        build_legacy_schema(connection)
        seed_legacy_relationships(connection)
        yield connection
      end
    ensure
      LegacyRecord.connection_pool.disconnect!
    end
  end

  def migrate(connection, direction)
    require Rails.root.join("db/migrate/20260903010000_convert_household_and_family_member_ids_to_uuids")
    migration = ConvertHouseholdAndFamilyMemberIdsToUuids.new
    migration.verbose = false
    migration.exec_migration(connection, direction)
  end

  def build_legacy_schema(connection)
    connection.create_table(:households) do |t|
      t.string :name, null: false
      t.timestamps null: false
    end
    connection.create_table(:family_members) do |t|
      t.integer :household_id, null: false
      t.string :name, null: false
      t.timestamps null: false
    end
    connection.create_table(:ingredient_aisle_mappings) do |t|
      t.integer :household_id
      t.string :name, null: false
    end
    connection.create_table(:meal_plans) do |t|
      t.integer :household_id, null: false
      t.date :week_start_date, null: false
    end
    connection.create_table(:pantry_items) do |t|
      t.integer :household_id, null: false
      t.string :name, null: false
    end
    connection.create_table(:recipes) do |t|
      t.integer :household_id, null: false
      t.string :title, null: false
    end
    connection.create_table(:meal_plan_slots) { |t| t.integer :family_member_id }
    connection.create_table(:recipe_requests) do |t|
      t.integer :family_member_id, null: false
      t.integer :recipe_id, null: false
      t.datetime :fulfilled_at
      t.date :week_start_date, null: false
    end

    add_legacy_indexes(connection)
    add_legacy_foreign_keys(connection)
  end

  def add_legacy_indexes(connection)
    connection.add_index :family_members, :household_id
    connection.add_index :ingredient_aisle_mappings, %i[household_id name]
    connection.add_index :ingredient_aisle_mappings, :household_id
    connection.add_index :meal_plans, %i[household_id week_start_date], unique: true
    connection.add_index :meal_plans, :household_id
    connection.add_index :pantry_items, %i[household_id name], unique: true
    connection.add_index :pantry_items, :household_id
    connection.add_index :recipes, %i[household_id title]
    connection.add_index :recipes, :household_id
    connection.add_index :meal_plan_slots, :family_member_id
    connection.add_index :recipe_requests, :family_member_id
    connection.add_index :recipe_requests, %i[recipe_id family_member_id fulfilled_at],
      name: "index_recipe_requests_on_active_request"
    connection.add_index :recipe_requests, %i[recipe_id family_member_id week_start_date],
      name: "idx_on_recipe_id_family_member_id_week_start_date_5f86066019"
  end

  def add_legacy_foreign_keys(connection)
    %i[family_members ingredient_aisle_mappings meal_plans pantry_items recipes].each do |table|
      connection.add_foreign_key table, :households
    end
    connection.add_foreign_key :meal_plan_slots, :family_members
    connection.add_foreign_key :recipe_requests, :family_members
  end

  def seed_legacy_relationships(connection)
    connection.execute <<~SQL
      INSERT INTO households (id, name, created_at, updated_at)
      VALUES (41, 'Legacy household', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
    connection.execute <<~SQL
      INSERT INTO family_members (id, household_id, name, created_at, updated_at)
      VALUES (73, 41, 'Legacy member', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    SQL
    connection.execute "INSERT INTO ingredient_aisle_mappings (household_id, name) VALUES (41, 'Rice')"
    connection.execute "INSERT INTO meal_plans (household_id, week_start_date) VALUES (41, '2026-08-31')"
    connection.execute "INSERT INTO pantry_items (household_id, name) VALUES (41, 'Salt')"
    connection.execute "INSERT INTO recipes (id, household_id, title) VALUES (101, 41, 'Soup')"
    connection.execute "INSERT INTO meal_plan_slots (family_member_id) VALUES (73)"
    connection.execute <<~SQL
      INSERT INTO recipe_requests (family_member_id, recipe_id, week_start_date)
      VALUES (73, 101, '2026-08-31')
    SQL
  end

  def column_types(connection)
    {
      households_primary_key: connection.primary_key(:households),
      households: column_signature(connection, :households, :id),
      family_members_primary_key: connection.primary_key(:family_members),
      family_members_id: column_signature(connection, :family_members, :id),
      family_members_household: column_signature(connection, :family_members, :household_id),
      ingredient_aisle_mappings_household: column_signature(connection, :ingredient_aisle_mappings, :household_id),
      meal_plans_household: column_signature(connection, :meal_plans, :household_id),
      pantry_items_household: column_signature(connection, :pantry_items, :household_id),
      recipes_household: column_signature(connection, :recipes, :household_id),
      meal_plan_slots_family_member: column_signature(connection, :meal_plan_slots, :family_member_id),
      recipe_requests_family_member: column_signature(connection, :recipe_requests, :family_member_id)
    }
  end

  def column_signature(connection, table, column)
    definition = connection.columns(table).find { |candidate| candidate.name == column.to_s }
    [ definition.type, definition.null ]
  end

  def expected_uuid_columns
    column_types_with(:string)
  end

  def expected_integer_columns
    column_types_with(:integer)
  end

  def column_types_with(type)
    {
      households_primary_key: "id",
      households: [ type, false ],
      family_members_primary_key: "id",
      family_members_id: [ type, false ],
      family_members_household: [ type, false ],
      ingredient_aisle_mappings_household: [ type, true ],
      meal_plans_household: [ type, false ],
      pantry_items_household: [ type, false ],
      recipes_household: [ type, false ],
      meal_plan_slots_family_member: [ type, true ],
      recipe_requests_family_member: [ type, false ]
    }
  end

  def expected_foreign_keys
    [
      [ "family_members", "households", "household_id" ],
      [ "ingredient_aisle_mappings", "households", "household_id" ],
      [ "meal_plan_slots", "family_members", "family_member_id" ],
      [ "meal_plans", "households", "household_id" ],
      [ "pantry_items", "households", "household_id" ],
      [ "recipe_requests", "family_members", "family_member_id" ],
      [ "recipes", "households", "household_id" ]
    ]
  end

  def foreign_keys(connection)
    expected_foreign_keys.map(&:first).uniq.flat_map do |table|
      connection.foreign_keys(table).map { |key| [ table, key.to_table, key.column ] }
    end.sort
  end

  def expected_indexes
    {
      "family_members" => [
        [ "index_family_members_on_household_id", [ "household_id" ], false ]
      ],
      "ingredient_aisle_mappings" => [
        [ "index_ingredient_aisle_mappings_on_household_id", [ "household_id" ], false ],
        [ "index_ingredient_aisle_mappings_on_household_id_and_name", [ "household_id", "name" ], false ]
      ],
      "meal_plan_slots" => [
        [ "index_meal_plan_slots_on_family_member_id", [ "family_member_id" ], false ]
      ],
      "meal_plans" => [
        [ "index_meal_plans_on_household_id", [ "household_id" ], false ],
        [ "index_meal_plans_on_household_id_and_week_start_date", [ "household_id", "week_start_date" ], true ]
      ],
      "pantry_items" => [
        [ "index_pantry_items_on_household_id", [ "household_id" ], false ],
        [ "index_pantry_items_on_household_id_and_name", [ "household_id", "name" ], true ]
      ],
      "recipe_requests" => [
        [ "idx_on_recipe_id_family_member_id_week_start_date_5f86066019", [ "recipe_id", "family_member_id", "week_start_date" ], false ],
        [ "index_recipe_requests_on_active_request", [ "recipe_id", "family_member_id", "fulfilled_at" ], false ],
        [ "index_recipe_requests_on_family_member_id", [ "family_member_id" ], false ]
      ],
      "recipes" => [
        [ "index_recipes_on_household_id", [ "household_id" ], false ],
        [ "index_recipes_on_household_id_and_title", [ "household_id", "title" ], false ]
      ]
    }
  end

  def affected_indexes(connection)
    expected_indexes.to_h do |table, _indexes|
      actual = connection.indexes(table).filter_map do |index|
        [ index.name, index.columns, index.unique ] if (index.columns & %w[household_id family_member_id]).any?
      end
      [ table, actual.sort ]
    end
  end

  def assert_preserved_relationships(connection, id_pattern:)
    household_id = connection.select_value("SELECT id FROM households").to_s
    family_member_id = connection.select_value("SELECT id FROM family_members").to_s
    assert_match id_pattern, household_id
    assert_match id_pattern, family_member_id

    household_references = %w[
      family_members ingredient_aisle_mappings meal_plans pantry_items recipes
    ].map { |table| connection.select_value("SELECT household_id FROM #{table}").to_s }
    family_member_references = %w[meal_plan_slots recipe_requests].map do |table|
      connection.select_value("SELECT family_member_id FROM #{table}").to_s
    end
    assert_equal [ household_id ] * 5, household_references
    assert_equal [ family_member_id ] * 2, family_member_references
    assert_empty connection.execute("PRAGMA foreign_key_check")
  end
end
