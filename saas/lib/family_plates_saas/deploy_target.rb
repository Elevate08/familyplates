# frozen_string_literal: true

module FamilyPlatesSaas
  class DeployTargetError < StandardError; end

  # The hosted service deploys to two Kamal destinations, production and
  # staging (saas/config/deploy.production.yml, deploy.staging.yml). Both run
  # RAILS_ENV=production, so Rails.env cannot tell them apart; each sets
  # FAMILYPLATES_DEPLOY_TARGET instead. A container handed the other one's
  # Stripe keys, webhook mode or staging settings refuses to boot, so Kamal's
  # health check fails and the running version keeps serving.
  #
  # Messages name the setting, never its value: they end up in deploy logs.
  module DeployTarget
    TARGETS = {
      "production" => { stripe_mode: "live", receive_test_events: "false" },
      "staging" => { stripe_mode: "test", receive_test_events: "true" }
    }.freeze

    SECRET_KEY_SOURCES = [ "STRIPE_SECRET_KEY", "STRIPE_PRIVATE_KEY", "Pay private_key" ].freeze
    PUBLISHABLE_KEY_SOURCES = [ "STRIPE_PUBLISHABLE_KEY", "STRIPE_PUBLIC_KEY", "Pay public_key" ].freeze
    PRICE_KEYS = %w[STRIPE_MONTHLY_PRICE_ID STRIPE_ANNUAL_PRICE_ID].freeze
    STAGING_ACCESS_KEYS = %w[STAGING_ACCESS_USERNAME STAGING_ACCESS_PASSWORD].freeze
    STAGING_MAIL_KEYS = %w[STAGING_MAIL_ALLOWLIST STAGING_MAIL_SINK].freeze

    def self.current(env: ENV)
      env["FAMILYPLATES_DEPLOY_TARGET"].presence
    end

    def self.staging?(environment: Rails.env, env: ENV)
      environment.production? && current(env: env) == "staging"
    end

    ENCRYPTION_KEYS = %w[ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT].freeze

    def self.verify!(environment: Rails.env, env: ENV, keys: StripeSandbox.configured_keys)
      found = problems(environment: environment, env: env, keys: keys) + encryption_problems(environment: environment, env: env)
      raise DeployTargetError, found.join("\n\n") if found.any?
    end

    # Operator TOTP secrets are encrypted at rest; a hosted production boot
    # without the keys would run with them readable or unusable.
    def self.encryption_problems(environment: Rails.env, env: ENV)
      return [] unless environment.production?

      ENCRYPTION_KEYS.select { |key| env[key].blank? }.map do |key|
        "#{key} is not set. Hosted production encrypts operator two-factor secrets and will not start without it."
      end
    end

    # The hosted bundle in production must say which destination it is: left
    # unset, none of the Stripe, webhook or staging checks below would run.
    def self.problems(environment: Rails.env, env: ENV, keys: StripeSandbox.configured_keys)
      return [] unless environment.production?

      target = current(env: env)
      return [ "FAMILYPLATES_DEPLOY_TARGET is not set. It must be production or staging on a hosted deploy." ] unless target

      settings = TARGETS[target]
      return [ "FAMILYPLATES_DEPLOY_TARGET must be production or staging." ] unless settings

      stripe_problems(target, settings, env, keys) + (target == "staging" ? staging_problems(env) : production_problems(env))
    end

    def self.stripe_problems(target, settings, env, keys)
      mode = settings[:stripe_mode]
      present = keys.select { |_source, key| key.present? }
      found = []

      if SECRET_KEY_SOURCES.none? { |source| present.key?(source) }
        found << "STRIPE_PRIVATE_KEY is not set. The #{target} deploy needs a Stripe #{mode} secret key."
      end

      # A secret setting takes a secret or restricted key and a publishable
      # setting a publishable one, both in the deploy's mode.
      wrong_secret = present.slice(*SECRET_KEY_SOURCES).reject { |_source, key| key.match?(/\A(sk|rk)_#{mode}_/) }.keys
      if wrong_secret.any?
        found << "#{wrong_secret.join(', ')} is not a Stripe #{mode} secret or restricted key (sk_#{mode}_ or rk_#{mode}_). " \
          "A publishable key does not belong there, and the #{target} deploy uses #{mode} mode only."
      end
      wrong_publishable = present.slice(*PUBLISHABLE_KEY_SOURCES).reject { |_source, key| key.match?(/\Apk_#{mode}_/) }.keys
      if wrong_publishable.any?
        found << "#{wrong_publishable.join(', ')} is not a Stripe #{mode} publishable key (pk_#{mode}_). " \
          "A secret key does not belong there, and the #{target} deploy uses #{mode} mode only."
      end
      unknown = present.keys - SECRET_KEY_SOURCES - PUBLISHABLE_KEY_SOURCES
      if unknown.any?
        found << "#{unknown.join(', ')} is not a Stripe key setting the #{target} deploy knows how to check."
      end

      unless env["STRIPE_SIGNING_SECRET"].to_s.start_with?("whsec_")
        found << "STRIPE_SIGNING_SECRET is not set to a Stripe webhook signing secret (whsec_)."
      end

      expected = settings[:receive_test_events]
      unless env["STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS"] == expected
        found << "STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS must be #{expected} on the #{target} deploy."
      end

      missing_prices = PRICE_KEYS.reject { |key| env[key].to_s.start_with?("price_") }
      if missing_prices.any?
        found << "#{missing_prices.join(', ')} must name a Stripe #{mode}-mode price (price_...)."
      end

      found
    end

    # Production must not carry staging's gate or mail routing: their presence
    # means the two destinations' settings were crossed.
    def self.production_problems(env)
      crossed = (STAGING_ACCESS_KEYS + STAGING_MAIL_KEYS).select { |key| env[key].present? }
      return [] if crossed.empty?

      [ "#{crossed.join(', ')} belongs to the staging deploy and must not be set on production." ]
    end

    def self.staging_problems(env)
      found = []
      missing = STAGING_ACCESS_KEYS.select { |key| env[key].blank? }
      if missing.any?
        found << "#{missing.join(', ')} is not set. Staging is closed to anyone without them."
      end
      if STAGING_MAIL_KEYS.all? { |key| env[key].blank? }
        found << "STAGING_MAIL_SINK or STAGING_MAIL_ALLOWLIST is required. " \
          "Staging does not send mail to addresses nobody has approved."
      end
      found
    end

    private_class_method :stripe_problems, :production_problems, :staging_problems
  end
end
