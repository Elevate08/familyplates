class EncryptPlatformAdminOtpSecret < ActiveRecord::Migration[8.1]
  # 183000 (not 120000) avoids the billing timestamp 20261003120000 already used in the shared tree.
  # Operator TOTP secrets were stored as plaintext. Active Record encryption
  # wraps the value in a JSON envelope that is longer than a string column is
  # guaranteed to hold, so the column is widened to text first. Nothing is
  # dropped and no row is deleted.
  #
  # Rows are rewritten in place only when both encryption settings are present;
  # otherwise they stay plaintext (still readable, because
  # support_unencrypted_data is on) and the migration says so. Re-run it once
  # the settings exist.
  class MigrationPlatformAdmin < ActiveRecord::Base
    self.table_name = "platform_admins"
    self.inheritance_column = nil
    encrypts :otp_secret
  end

  def up
    change_column :platform_admins, :otp_secret, :text, null: false

    unless encryption_configured?
      say "Active Record encryption keys are not set - leaving operator two-factor secrets in plaintext."
      say "Set ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY and ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT and re-run to encrypt them."
      return
    end

    say_with_time "encrypting stored operator two-factor secrets" do
      converted = 0
      MigrationPlatformAdmin.reset_column_information
      MigrationPlatformAdmin.find_each do |admin|
        raw = admin.read_attribute_before_type_cast(:otp_secret)
        next if raw.blank?
        next if raw.start_with?("{\"p\":") # already an encrypted payload

        admin.encrypt
        converted += 1
      end
      converted
    end
  end

  # Deliberately irreversible: rolling back would write the secrets back to the
  # database in clear text.
  def down
    raise ActiveRecord::IrreversibleMigration,
      "Refusing to rewrite operator two-factor secrets back to plaintext."
  end

  private

  def encryption_configured?
    ActiveRecord::Encryption.config.has_primary_key? &&
      ActiveRecord::Encryption.config.has_key_derivation_salt?
  end
end
