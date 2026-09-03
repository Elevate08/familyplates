class EncryptGoogleServiceAccountJson < ActiveRecord::Migration[8.1]
  # Rewrites existing plaintext credentials through the encrypted attribute.
  #
  # support_unencrypted_data is on, so an unconverted row still reads correctly
  # if this is skipped - which it will be on an install that has not set the
  # encryption keys yet. Better to leave the row readable and say so than to
  # abort an upgrade over a credential the household may not even use.
  def up
    unless encryption_configured?
      say "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY is not set - leaving Google credentials in plaintext."
      say "Set the key and re-run this migration to encrypt them. See docs/getting-started.md."
      return
    end

    say_with_time "encrypting stored Google service account credentials" do
      converted = 0
      Household.reset_column_information
      Household.find_each do |household|
        raw = household.read_attribute_before_type_cast(:google_service_account_json)
        next if raw.blank?
        next if raw.start_with?("{\"p\":") # already an encrypted payload

        household.update_column(:google_service_account_json, nil)
        household.update!(google_service_account_json: raw)
        converted += 1
      end
      converted
    end
  end

  # Deliberately irreversible. Rolling this back would write private keys back
  # to the database in clear text, which is the state this migration exists to
  # leave behind.
  def down
    raise ActiveRecord::IrreversibleMigration,
      "Refusing to rewrite Google service account keys back to plaintext."
  end

  private

  def encryption_configured?
    ActiveRecord::Encryption.config.has_primary_key? &&
      ActiveRecord::Encryption.config.has_key_derivation_salt?
  end
end
