# frozen_string_literal: true

require "openssl"

# Replaces the plaintext session token columns with SHA-256 digests. Existing
# rows are hashed in place, so every signed-in browser, kiosk and operator stays
# signed in: their cookies still carry the raw token, which now matches by
# digest. The plaintext cannot be recovered, so rolling back signs everyone out.
#
# The column is renamed with raw ALTER TABLE on purpose. Rails' rename_column,
# remove_column and change_column_null all rebuild the table on SQLite, and the
# rebuild's DROP TABLE fires device_grants' ON DELETE CASCADE inside the
# migration transaction - silently deleting every pairing that points at a
# session. A native rename keeps the table, its NOT NULL and its unique index.
class HashSessionTokens < ActiveRecord::Migration[8.1]
  TABLES = %w[sessions platform_admin_sessions].freeze

  def up
    TABLES.each do |table|
      execute "ALTER TABLE #{quote_table_name(table)} RENAME COLUMN token TO token_digest"

      select_rows("SELECT id, token_digest FROM #{quote_table_name(table)}").each do |id, token|
        execute <<~SQL.squish
          UPDATE #{quote_table_name(table)}
          SET token_digest = #{quote(OpenSSL::Digest::SHA256.hexdigest(token.to_s))}
          WHERE id = #{quote(id)}
        SQL
      end

      rename_index table, "index_#{table}_on_token", "index_#{table}_on_token_digest"
    end
  end

  def down
    TABLES.each do |table|
      # Digests cannot be turned back into tokens. Deleting the sessions
      # cascades to their device grants, which is correct: those devices are
      # signed out too.
      execute "DELETE FROM #{quote_table_name(table)}"
      execute "ALTER TABLE #{quote_table_name(table)} RENAME COLUMN token_digest TO token"
      rename_index table, "index_#{table}_on_token_digest", "index_#{table}_on_token"
    end
  end
end
