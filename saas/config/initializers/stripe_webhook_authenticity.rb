# frozen_string_literal: true

# Pay verifies the Stripe signature, then processes every delivery, including
# a second delivery of an event it has already handled. Stripe retries for
# days, and the signature is fresh each time, so the timestamp window does
# not stop a repeat. charge and subscription syncs re-read Stripe, but
# invoice.payment_failed sends mail from the payload and customer.deleted
# cancels the household from the payload alone.
module StripeWebhookReplayGuard
  private

  def queue_event(event)
    return unless claim_stripe_event!(event)

    super
  rescue StandardError
    release_stripe_event!(event)
    raise
  end

  def claim_stripe_event!(event)
    id = event.respond_to?(:id) ? event.id.to_s : ""
    return false if id.blank?

    stripe_event_store.write(stripe_event_key(id), true, expires_in: 3.days, unless_exist: true) != false
  end

  def release_stripe_event!(event)
    id = event.respond_to?(:id) ? event.id.to_s : ""
    stripe_event_store.delete(stripe_event_key(id)) if id.present?
  end

  def stripe_event_key(id)
    "stripe_webhook_event:#{id}"
  end

  # The same store as the sign-in limiter: solid cache in production, so a
  # second Puma worker sees the claim, and a real store in tests (Rails.cache
  # is a null store there, which would make this check a no-op).
  def stripe_event_store
    Rails.application.config.pin_attempt_store
  end
end

# customer.deleted marks every local subscription canceled without asking
# Stripe. A signed event whose customer is still active — a replay after the
# household subscribed again, or a signing secret used to forge the type —
# would end access Stripe is still billing. Confirm the customer is gone first.
module StripeCustomerDeletionConfirmation
  def call(event)
    super if stripe_customer_gone?(event.data.object.id)
  end

  private

  def stripe_customer_gone?(customer_id)
    customer = ::Stripe::Customer.retrieve(customer_id)
    customer.respond_to?(:deleted) && customer.deleted == true
  rescue ::Stripe::InvalidRequestError => error
    error.http_status == 404
  end
end

Rails.application.config.to_prepare do
  replay = StripeWebhookReplayGuard
  controller = Pay::Webhooks::StripeController
  controller.prepend(replay) unless controller.ancestors.include?(replay)

  deletion = StripeCustomerDeletionConfirmation
  handler = Pay::Stripe::Webhooks::CustomerDeleted
  handler.prepend(deletion) unless handler.ancestors.include?(deletion)
end
