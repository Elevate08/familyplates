# frozen_string_literal: true

# Added to Pay::Subscription by the engine. Every way a subscription reaches
# this app (the return from Checkout, a webhook, a replay) saves it through
# Pay, so confirming here covers them all without depending on their order.
module BillingConsent::SubscriptionHook
  extend ActiveSupport::Concern

  included do
    after_commit :confirm_billing_consent, on: %i[create update]
  end

  private

  # Access comes from the subscription Pay just saved. A failure here must not
  # fail that sync; the consent stays unconfirmed and the error is reported.
  def confirm_billing_consent
    BillingConsent.confirm_subscription(self)
  rescue StandardError => e
    Rails.logger.error("[BillingConsent] confirming for subscription #{processor_id} failed: #{e.class}: #{e.message}")
    Rails.error.report(e, handled: true)
  end
end
