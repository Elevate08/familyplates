# Active Record encryption keys.
#
# Rails' default is to read these from config/credentials.yml.enc, which needs
# RAILS_MASTER_KEY. This app ships no master key and deploys with SECRET_KEY_BASE
# alone, so credentials are unreadable in production and environment variables
# are the only source that works. config.active_record.encryption is splatted
# after the credentials lookup in Rails' own initializer, so these win when set
# and fall back to credentials for anyone who does use a master key.
#
# Deliberately NOT derived from SECRET_KEY_BASE: rotating that key is the
# remedy for a leaked session secret, and it must not also destroy every
# encrypted value in the database.
#
# Generate a pair with:
#   openssl rand -hex 32   # ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
#   openssl rand -hex 32   # ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
#
# There is no deterministic_key because nothing is queried by its encrypted
# value; add one only if a deterministic: true attribute is ever introduced.
Rails.application.configure do
  primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence
  salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence

  config.active_record.encryption.primary_key = primary_key if primary_key
  config.active_record.encryption.key_derivation_salt = salt if salt

  # Lets an existing database be read while its rows are still plaintext, so an
  # upgrade does not have to encrypt everything before the app will start. The
  # migration converts the rows; this covers the window in between, and any row
  # written by a version that predates the keys being set.
  config.active_record.encryption.support_unencrypted_data = true
end
