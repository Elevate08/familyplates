# frozen_string_literal: true

module FamilyPlatesSaas
  class LiveStripeKeyError < StandardError; end

  # A test run talks to Stripe through a sandbox or not at all. The real-checkout
  # Playwright test and the webhook suites create customers and pay with test
  # cards; handed a live key they would do that to the real account. So the test
  # environment will not boot with one, wherever it came from.
  module StripeSandbox
    ENV_KEYS = %w[STRIPE_SECRET_KEY STRIPE_PRIVATE_KEY STRIPE_PUBLISHABLE_KEY STRIPE_PUBLIC_KEY].freeze
    SANDBOX_KEY = /\A(sk|rk|pk)_test_/

    def self.verify!(environment: Rails.env, keys: configured_keys)
      return unless environment.test?

      live = keys.select { |_source, key| key.present? && !key.match?(SANDBOX_KEY) }.keys
      return if live.empty?

      raise FamilyPlatesSaas::LiveStripeKeyError, "#{live.join(', ')} is not a Stripe test key (sk_test_, rk_test_ or pk_test_). " \
        "Tests run against a Stripe sandbox only."
    end

    def self.configured_keys
      keys = ENV_KEYS.index_with { |name| ENV[name] }
      if defined?(Pay::Stripe)
        keys["Pay private_key"] = Pay::Stripe.private_key
        keys["Pay public_key"] = Pay::Stripe.public_key
      end
      keys
    end
  end
end
