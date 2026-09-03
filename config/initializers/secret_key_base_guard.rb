# secret_key_base signs the cookie that says which family member you are, and
# set_current_family_member trusts that cookie outright. A predictable value
# therefore lets anyone mint an organizer session without touching a single
# guarded endpoint - which is why this refuses to boot rather than warn.
#
# The shipped compose file used to default it to a literal published in this
# repository, and both the README and the getting-started guide printed that
# literal on the line operators copy.
if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
  Rails.application.config.after_initialize do
    secret = Rails.application.secret_key_base.to_s

    KNOWN_PLACEHOLDERS = %w[
      replace_with_a_secure_random_hex_string
      changeme
      secret
    ].freeze

    if secret.blank?
      abort <<~MESSAGE
        FATAL: SECRET_KEY_BASE is not set.

        It signs the session cookie that identifies who is signed in. Generate one:

            openssl rand -hex 64
      MESSAGE
    end

    if KNOWN_PLACEHOLDERS.include?(secret.downcase) || secret.length < 32
      abort <<~MESSAGE
        FATAL: SECRET_KEY_BASE is a placeholder or too short to be safe.

        This value signs the session cookie that identifies who is signed in, so a
        guessable one lets anyone sign in as a household organizer. If this
        instance has been running with it, treat the install as compromised:
        generate a new key, restart, and review your family roster.

            openssl rand -hex 64
      MESSAGE
    end
  end
end
