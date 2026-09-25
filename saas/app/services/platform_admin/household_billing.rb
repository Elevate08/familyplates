# frozen_string_literal: true

module PlatformAdmin
  # What an operator can do to a household's billing from the console: cancel
  # its subscription, refund a charge, or give it free months. Stripe stays the
  # system of record; each call goes through Pay or the Stripe API, and the
  # webhooks that follow keep the app in step.
  class HouseholdBilling
    class Error < StandardError; end

    MAX_COMP_MONTHS = 12

    def initialize(household)
      @household = household
    end

    # At period end the household keeps what it paid for; immediately ends
    # access now, with no refund (refund a charge separately if one is owed).
    def cancel_subscription!(immediately:)
      sub = active_subscription || raise(Error, "No active subscription to cancel.")
      if !immediately && sub.ends_at.present?
        raise Error, "The subscription already ends on #{sub.ends_at.to_date.to_formatted_s(:long)}."
      end

      immediately ? sub.cancel_now! : sub.cancel
      sub
    rescue Pay::Error => e
      raise Error, "Stripe refused the cancellation: #{e.message}"
    end

    # amount_cents nil refunds whatever has not been refunded yet.
    def refund_charge!(charge_id, amount_cents: nil)
      charge = @household.pay_charges.find(charge_id)
      refundable = charge.amount - charge.amount_refunded.to_i
      amount = amount_cents || refundable
      unless amount.positive? && amount <= refundable
        raise Error, "A refund must be between $0.01 and #{format_cents(refundable)}."
      end

      charge.refund!(amount)
      amount
    rescue Pay::Error => e
      raise Error, "Stripe refused the refund: #{e.message}"
    end

    # A paying household's next charge moves back by the months given, so
    # billing resumes by itself. Stripe does this by extending the trial end
    # of an active subscription; a coupon would not work, since a repeating
    # coupon counts calendar months and an annual renewal can be a year off.
    # A household that is not paying gets its free trial extended instead.
    def comp!(months)
      unless months.is_a?(Integer) && months.between?(1, MAX_COMP_MONTHS)
        raise Error, "Comp between 1 and #{MAX_COMP_MONTHS} months."
      end

      sub = active_subscription
      return extend_trial!(months) unless sub

      raise Error, "Only a Stripe subscription can be comped here." unless sub.is_a?(Pay::Stripe::Subscription)
      raise Error, "The subscription is set to end; it has nothing left to comp." if sub.ends_at.present?

      apply_free_months!(sub, months)
      :subscription
    rescue ::Stripe::StripeError, Pay::Error => e
      raise Error, "Stripe refused the comp: #{e.message}"
    end

    private

    def active_subscription
      sub = @household.payment_processor&.subscription
      sub if sub&.active?
    end

    def extend_trial!(months)
      from = [ @household.trial_ends_at, Time.current ].max
      @household.update!(trial_extended_until: from + months.months)
      :trial
    end

    def apply_free_months!(sub, months)
      from = [ sub.trial_ends_at, sub.current_period_end, Time.current ].compact.max
      ::Stripe::Subscription.update(sub.processor_id, trial_end: (from + months.months).to_i, proration_behavior: "none")
      sub.sync!
    end

    def format_cents(cents)
      ActiveSupport::NumberHelper.number_to_currency(cents / 100.0)
    end
  end
end
