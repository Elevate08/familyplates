# frozen_string_literal: true

# The first charge for a confirmed consent as the payment provider reports
# it: what was actually paid after any discount, the period it paid for, and
# when the subscription next renews. The acknowledgment states these, so
# they are read from Stripe itself, never from a webhook payload, a return
# URL or the plan table. Raises Unverified until Stripe reports the invoice
# paid; the acknowledgment waits and tries again.
module BillingConsent::PaymentDetails
  class Unverified < StandardError; end

  def self.fetch(consent)
    subscription = Pay::Subscription.find_by(id: consent.pay_subscription_id)
    raise Unverified, "consent #{consent.id} has no subscription" unless subscription

    case subscription.customer&.processor
    when "stripe" then from_stripe(consent)
    when "fake_processor" then from_simulation(consent, subscription)
    else raise Unverified, "subscription #{subscription.id} has no supported payment processor"
    end
  end

  def self.from_stripe(consent)
    subscription = ::Stripe::Subscription.retrieve(consent.subscription_processor_id)
    invoices = ::Stripe::Invoice.list({ subscription: consent.subscription_processor_id, limit: 10 }).data
    paid = invoices.select { |invoice| invoice[:status] == "paid" }
    invoice = paid.find { |candidate| candidate[:billing_reason] == "subscription_create" } || paid.min_by { |candidate| candidate[:created].to_i }
    raise Unverified, "Stripe reports no paid invoice for #{consent.subscription_processor_id} yet" unless invoice

    line = Array(invoice[:lines] && invoice[:lines][:data]).find { |candidate| candidate[:period] }
    raise Unverified, "invoice #{invoice[:id]} has no billing period" unless line

    transitions = invoice[:status_transitions]
    {
      provider_invoice_id: invoice[:id],
      paid_amount_minor_units: invoice[:amount_paid],
      paid_currency: invoice[:currency],
      paid_discount_minor_units: Array(invoice[:total_discount_amounts]).sum { |discount| discount[:amount].to_i },
      paid_at: Time.zone.at((transitions && transitions[:paid_at]) || invoice[:created]),
      paid_period_start: Time.zone.at(line[:period][:start]),
      paid_period_end: Time.zone.at(line[:period][:end]),
      next_renewal_at: next_renewal(subscription)
    }
  end

  # Nil when the subscription will not renew.
  def self.next_renewal(subscription)
    return if subscription[:status] != "active" || subscription[:cancel_at_period_end] || subscription[:cancel_at]

    item = Array(subscription[:items] && subscription[:items][:data]).first
    period_end = (item && item[:current_period_end]) || subscription[:current_period_end]
    Time.zone.at(period_end) if period_end
  end

  # Development and tests without Stripe: the simulated subscription is the
  # provider, and it charges the plan price with no discount.
  def self.from_simulation(consent, subscription)
    {
      provider_invoice_id: nil,
      paid_amount_minor_units: consent.amount_minor_units,
      paid_currency: consent.currency,
      paid_discount_minor_units: 0,
      paid_at: subscription.created_at,
      paid_period_start: subscription.current_period_start,
      paid_period_end: subscription.current_period_end,
      next_renewal_at: subscription.ends_at ? nil : subscription.current_period_end
    }
  end
end
