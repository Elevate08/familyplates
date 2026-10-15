# frozen_string_literal: true

module BillingConsentTestHelper
  # Hands each acknowledgment to a lambda instead of a mail server, so a test
  # can accept it, refuse it, or accept it and then lose the connection.
  class ScriptedDelivery
    cattr_accessor :behavior

    def initialize(*) = nil

    def deliver!(mail)
      self.class.behavior.call(mail)
    end
  end

  # What the subscription page posts once the billing owner ticks the box
  # beside a plan's renewal terms.
  def consent_params(plan, household:, user:)
    {
      plan: plan.to_s,
      accept_renewal_terms: "1",
      offer_token: BillingOffer.for(plan).token_for(household: household, user: user)
    }
  end

  # The payment details the acknowledgment states, as if already read from
  # Stripe.
  def verified_payment(amount: 5000, discount: 0, paid_at: Time.utc(2026, 10, 3, 12), period_end: Time.utc(2027, 10, 3, 12))
    {
      provider_invoice_id: "in_verified", paid_amount_minor_units: amount, paid_currency: "usd",
      paid_discount_minor_units: discount, paid_at: paid_at, paid_period_start: paid_at,
      paid_period_end: period_end, next_renewal_at: period_end
    }
  end

  # Stands in for Stripe's record of a subscription's first invoice. Pass
  # `subscription:` to answer Stripe::Subscription.retrieve too; otherwise
  # whatever already stubs it does.
  def with_stripe_payment(subscription_id, amount_paid:, discount: 0, status: "paid", period_start: Time.utc(2026, 10, 3, 12),
                          period_end: Time.utc(2026, 11, 3, 12), subscription: nil)
    invoice = {
      id: "in_#{subscription_id}", object: "invoice", status: status, billing_reason: "subscription_create",
      amount_paid: status == "paid" ? amount_paid : 0, currency: "usd", created: period_start.to_i,
      status_transitions: { paid_at: status == "paid" ? period_start.to_i : nil },
      total_discount_amounts: discount.positive? ? [ { amount: discount, discount: "di_test" } ] : [],
      lines: { object: "list", data: [
        { id: "il_#{subscription_id}", object: "line_item", amount: amount_paid,
          period: { start: period_start.to_i, end: period_end.to_i } }
      ] }
    }
    requested = []
    original_list = Stripe::Invoice.method(:list)
    original_retrieve = Stripe::Subscription.method(:retrieve)
    Stripe::Invoice.define_singleton_method(:list) do |params, *|
      requested << params
      Stripe::ListObject.construct_from(object: "list", data: [ invoice ])
    end
    if subscription
      Stripe::Subscription.define_singleton_method(:retrieve) { |*| Stripe::Subscription.construct_from(subscription) }
    end
    yield requested
  ensure
    Stripe::Invoice.define_singleton_method(:list, original_list)
    Stripe::Subscription.define_singleton_method(:retrieve, original_retrieve)
  end

  def stripe_subscription(id, period_end: Time.utc(2026, 11, 3, 12), cancel_at_period_end: false)
    {
      id: id, object: "subscription", status: "active", cancel_at_period_end: cancel_at_period_end, cancel_at: nil,
      items: { object: "list", data: [ { id: "si_#{id}", object: "subscription_item", current_period_end: period_end.to_i } ] }
    }
  end

  def with_delivery(behavior)
    ActionMailer::Base.add_delivery_method :billing_consent_scripted, ScriptedDelivery
    ScriptedDelivery.behavior = behavior
    previous = BillingConsentMailer.delivery_method
    BillingConsentMailer.delivery_method = :billing_consent_scripted
    yield
  ensure
    BillingConsentMailer.delivery_method = previous
  end

  # Stands in for Stripe's list of a customer's Checkout sessions.
  def with_checkout_sessions(sessions)
    requested = []
    original = Stripe::Checkout::Session.method(:list)
    Stripe::Checkout::Session.define_singleton_method(:list) do |params, *|
      requested << params
      Stripe::ListObject.construct_from(object: "list", data: sessions)
    end
    yield requested
  ensure
    Stripe::Checkout::Session.define_singleton_method(:list, original)
  end

  # Stands in for Stripe's answer about one Checkout session by id: the
  # session, or an error to raise as if Stripe could not be reached.
  def with_checkout_session_retrieve(answer)
    requested = []
    original = Stripe::Checkout::Session.method(:retrieve)
    Stripe::Checkout::Session.define_singleton_method(:retrieve) do |id, *|
      requested << id
      raise answer if answer.is_a?(Exception)

      Stripe::Checkout::Session.construct_from(answer)
    end
    yield requested
  ensure
    Stripe::Checkout::Session.define_singleton_method(:retrieve, original)
  end

  # Stands in for Pay syncing a complete Checkout session: saves, for the
  # household's Stripe customer, the subscription that session started.
  def with_checkout_sync(household, subscription_id:, status:, consent:)
    synced = []
    original = Pay::Stripe.method(:sync_checkout_session)
    Pay::Stripe.define_singleton_method(:sync_checkout_session) do |session_id, **|
      synced << session_id
      household.payment_processor.subscriptions.find_or_initialize_by(processor_id: subscription_id).update!(
        name: "default", processor_plan: consent.stripe_price_id || "price_inline", status: status,
        current_period_start: Time.current, current_period_end: 1.month.from_now,
        metadata: { "billing_consent_id" => consent.id }
      )
    end
    yield synced
  ensure
    Pay::Stripe.define_singleton_method(:sync_checkout_session, original)
  end
end
