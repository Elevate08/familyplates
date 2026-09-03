require "securerandom"

class ConvertHouseholdAndFamilyMemberIdsToUuids < ActiveRecord::Migration[8.1]
  HOUSEHOLD_FOREIGN_KEYS = {
    family_members: false,
    ingredient_aisle_mappings: true,
    meal_plans: false,
    pantry_items: false,
    recipes: false
  }.freeze
  FAMILY_MEMBER_FOREIGN_KEYS = {
    meal_plan_slots: true,
    recipe_requests: false
  }.freeze

  def up
    household_ids = uuid_mapping_for(:households)
    family_member_ids = uuid_mapping_for(:family_members)

    connection.disable_referential_integrity do
      change_foreign_key_types(:string)
      change_primary_key_type :households, :string
      change_primary_key_type :family_members, :string
      suppress_messages do
        replace_ids :households, household_ids
        replace_foreign_keys HOUSEHOLD_FOREIGN_KEYS.keys, :household_id, household_ids
        replace_ids :family_members, family_member_ids
        replace_foreign_keys FAMILY_MEMBER_FOREIGN_KEYS.keys, :family_member_id, family_member_ids
      end
    end
  end

  def down
    household_ids = integer_mapping_for(:households)
    family_member_ids = integer_mapping_for(:family_members)

    connection.disable_referential_integrity do
      suppress_messages do
        replace_ids :households, household_ids
        replace_foreign_keys HOUSEHOLD_FOREIGN_KEYS.keys, :household_id, household_ids
        replace_ids :family_members, family_member_ids
        replace_foreign_keys FAMILY_MEMBER_FOREIGN_KEYS.keys, :family_member_id, family_member_ids
      end
      change_foreign_key_types(:integer)
      change_primary_key_type :households, :integer
      change_primary_key_type :family_members, :integer
    end
  end

  private

  def uuid_mapping_for(table)
    connection.select_values("SELECT id FROM #{connection.quote_table_name(table)}").to_h do |id|
      [ id.to_s, SecureRandom.uuid ]
    end
  end

  def integer_mapping_for(table)
    connection.select_values(
      "SELECT id FROM #{connection.quote_table_name(table)} ORDER BY created_at, id"
    ).each_with_index.to_h { |id, index| [ id.to_s, index + 1 ] }
  end

  def change_foreign_key_types(type)
    HOUSEHOLD_FOREIGN_KEYS.each do |table, nullable|
      change_column table, :household_id, type, null: nullable
    end
    FAMILY_MEMBER_FOREIGN_KEYS.each do |table, nullable|
      change_column table, :family_member_id, type, null: nullable
    end
  end

  def change_primary_key_type(table, type)
    change_column table, :id, type, null: false, primary_key: true
  end

  def replace_ids(table, mapping)
    mapping.each do |old_id, new_id|
      update_key table, :id, old_id, new_id
    end
  end

  def replace_foreign_keys(tables, column, mapping)
    tables.each do |table|
      mapping.each do |old_id, new_id|
        update_key table, column, old_id, new_id
      end
    end
  end

  def update_key(table, column, old_id, new_id)
    quoted_table = connection.quote_table_name(table)
    quoted_column = connection.quote_column_name(column)
    execute <<~SQL.squish
      UPDATE #{quoted_table}
      SET #{quoted_column} = #{connection.quote(new_id)}
      WHERE #{quoted_column} = #{connection.quote(old_id)}
    SQL
  end
end
