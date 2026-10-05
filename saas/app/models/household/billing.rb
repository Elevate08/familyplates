# Trials, Stripe subscriptions through Pay, and whether a household may use
# the kitchen. Only the hosted edition includes this; an appliance household
# is never billed, so the core never asks.
module Household::Billing
  extend ActiveSupport::Concern

  FREE_TRIAL_DAYS = 14
  PAST_DUE_GRACE_DAYS = 7

  # The one source for what each plan charges. The subscription page, the
  # consent record, Checkout and the acknowledgment email all read it through
  # BillingOffer, and a configured Stripe price must match it.
  PLANS = {
    monthly: {
      name: "Monthly",
      amount_minor_units: 500,
      currency: "usd",
      interval: "month",
      stripe_price_id: ENV["STRIPE_MONTHLY_PRICE_ID"].presence || "price_monthly",
      description: "Full family kitchen access, billed monthly"
    },
    annual: {
      name: "Annual",
      amount_minor_units: 5000,
      currency: "usd",
      interval: "year",
      stripe_price_id: ENV["STRIPE_ANNUAL_PRICE_ID"].presence || "price_annual",
      description: "Best value for families, billed once a year"
    }
  }.freeze

  included do
    pay_customer default: true

    # The user, not a profile, who may subscribe, cancel or open the Stripe
    # portal. Nil for a legacy household nobody has evidence for, and after
    # the owner's account is deleted; PlatformAdmin::BillingOwnerRecovery
    # assigns one. Claiming or switching profiles never changes it.
    belongs_to :billing_owner, class_name: "User", foreign_key: :billing_owner_user_id,
      optional: true, inverse_of: :billing_owned_households

    # Prepended so it runs ahead of the dependent: destroy/nullify hooks.
    before_destroy :cleanup_pay_customers, prepend: true

    delegate :subscribed?, :on_trial?, :on_trial_or_subscribed?, to: :payment_processor, allow_nil: true

    alias_method :pay_customer_email, :email
  end

  SubscriptionCancellationFailure = Data.define(:subscription, :error)

  # Stripe statuses a subscription never leaves and is never billed in again.
  TERMINAL_SUBSCRIPTION_STATUSES = %w[canceled incomplete_expired].freeze

  # Cancel now, no refund. Returns a SubscriptionCancellationFailure for each
  # subscription Stripe did not cancel; any failure means the household must
  # not be deleted, since its Pay records are the only link to Stripe. Every
  # subscription not yet terminal is cancelled, not just Pay's active scope:
  # past_due, unpaid, paused and incomplete subscriptions still exist in
  # Stripe and can still charge. Each success is recorded locally as it
  # happens, so a retry skips what already cancelled. Not named
  # cancel_active_pay_subscriptions!: Pay's pay_customer defines that, without
  # the rescue, and would shadow this.
  def cancel_subscriptions_before_deletion!
    pay_subscriptions.where.not(status: TERMINAL_SUBSCRIPTION_STATUSES).filter_map do |sub|
      sub.cancel_now!
      nil
    rescue StandardError => e
      next if ended_at_stripe!(sub)

      Rails.logger.warn "[Pay] Unable to cancel subscription #{sub.id} (#{sub.processor_id}) during household deletion: #{e.class}: #{e.message}"
      SubscriptionCancellationFailure.new(subscription: sub, error: e)
    end
  end

  def pay_customer_name
    name
  end

  def billing_owner?(user)
    user.present? && billing_owner_user_id.present? && billing_owner_user_id == user.id
  end

  # One UTC instant, whatever zone the household is in or later moves to:
  # FREE_TRIAL_DAYS of elapsed time from creation, or the operator's
  # extension, or when verified paid service started, whichever was set
  # last. Never a local midnight, and a DST change cannot move it.
  def trial_ends_at
    trial_extended_until || ((created_at || Time.current).utc + FREE_TRIAL_DAYS.days)
  end

  # Active up to, not including, the instant it ends.
  def trial_active?
    Time.current < trial_ends_at
  end

  # Whole days still to run, rounded up: 13 days and an hour is 14. Under a
  # day is 1 here; trial_less_than_one_day_left? lets a page say so instead.
  def trial_days_left
    [ ((trial_ends_at - Time.current) / 1.day).ceil, 0 ].max
  end

  def trial_less_than_one_day_left?
    trial_active? && (trial_ends_at - Time.current) < 1.day
  end

  # Paid service has started at `at`, verified by Stripe reporting the
  # subscription active (BillingConsent#confirm!), so whatever free trial was
  # left ends then. Never lengthens a trial: a payment confirmed after the
  # trial ran out leaves its end where it was.
  def end_trial_for_paid_start!(at)
    return unless at < trial_ends_at

    update_columns(trial_extended_until: at)
  end

  # Subscription statuses that mean a payment once succeeded. Incomplete is
  # a first payment still pending; incomplete_expired is one that failed.
  CONVERTED_SUBSCRIPTION_STATUSES = %w[active trialing past_due unpaid paused canceled].freeze

  # Whether this household ever paid: a subscription Stripe moved past its
  # first payment (checked first: it settles nearly every paying household in
  # one query), or a confirmed billing consent. The trial banner asks on every
  # page, so the answer is kept for this object until it is reloaded.
  def paid_conversion?
    return @paid_conversion unless @paid_conversion.nil?

    @paid_conversion = pay_subscriptions.where(status: CONVERTED_SUBSCRIPTION_STATUSES).exists? ||
      BillingConsent.confirmed.where(household_id: id).exists?
  end

  # A subscription payment may have been made but is not confirmed: Checkout
  # completed and the first payment of the subscription it started is still
  # pending, or a Checkout request ended without learning whether Stripe
  # started it. A Checkout merely opened (or abandoned) is not a payment, so
  # it is not pending. None of this ends the trial.
  def subscription_payment_pending?
    return @subscription_payment_pending unless @subscription_payment_pending.nil?

    @subscription_payment_pending = pay_subscriptions.where(status: "incomplete").exists? ||
      BillingConsent.held_checkouts.where(household_id: id, checkout_state: "unknown").exists?
  end

  def reload(*)
    @paid_conversion = @subscription_payment_pending = nil
    super
  end

  # What the trial banner shows: :trial while the free trial runs unpaid,
  # :expired once it has ended unpaid, :pending while a payment awaits
  # confirmation, and nil once the household has paid (or on an appliance).
  def trial_banner_state
    return unless FamilyPlates.config.hosted?
    return if paid_conversion?
    return :pending if subscription_payment_pending?

    trial_active? ? :trial : :expired
  end

  def past_due_grace_active?
    sub = payment_processor&.subscription
    return false unless sub&.status == "past_due"

    ref_time = sub.current_period_end || sub.updated_at
    ref_time.present? && Time.current < (ref_time + PAST_DUE_GRACE_DAYS.days)
  end

  def active_subscription?
    payment_processor&.subscribed? || false
  end

  def entitled?
    return true unless FamilyPlates.config.hosted?

    active_subscription? || trial_active? || past_due_grace_active?
  end

  def subscription_plan_key
    sub = payment_processor&.subscription
    return nil unless sub

    plan_str = sub.processor_plan.to_s.downcase
    return :monthly if plan_str == "monthly" || plan_str == PLANS[:monthly][:stripe_price_id]
    return :annual if plan_str == "annual" || plan_str == PLANS[:annual][:stripe_price_id]

    start_time = sub.current_period_start || sub.created_at
    if sub.current_period_end && start_time
      days = ((sub.current_period_end - start_time) / 1.day).round
      return :annual if days > 60
      return :monthly
    end

    :monthly
  end

  def subscription_plan_name
    key = subscription_plan_key
    return nil unless key

    PLANS[key]&.dig(:name) || key.to_s.titleize
  end

  def subscription_expires_at
    sub = current_subscription
    if sub
      sub.ends_at || sub.current_period_end || sub.trial_ends_at
    else
      trial_ends_at
    end
  end

  def subscription_billing_label
    return "Appliance" unless FamilyPlates.config.hosted?

    sub = current_subscription
    if sub
      if sub.ends_at.present?
        sub.ends_at.future? ? "Access until" : "Access expired"
      elsif sub.status == "past_due"
        past_due_grace_active? ? "Grace ends" : "Past due"
      elsif sub.status == "trialing"
        "Trial ends"
      elsif sub.status == "paused"
        "Paused"
      elsif sub.status == "unpaid"
        "Unpaid"
      elsif sub.status == "incomplete" || sub.status == "incomplete_expired"
        "Incomplete"
      elsif sub.active?
        "Renews"
      elsif sub.canceled?
        "Canceled"
      else
        "Expires"
      end
    elsif trial_active?
      "Trial ends"
    else
      "Trial expired"
    end
  end

  def applied_promotion_code
    promotion_code.presence || current_subscription&.metadata&.dig("promotion_code")
  end

  # The operator-assigned promotion Checkout should apply, if Stripe knows it
  # and it can still be redeemed.
  def checkout_promotion
    return if promotion_code.blank?

    program = PromotionProgram.find_by(code: promotion_code)
    program if program&.provider_promotion_code_id.present? && program.currently_active?
  end

  def subscription_status
    return :appliance unless FamilyPlates.config.hosted?

    sub = current_subscription
    if sub
      return :trialing if sub.status == "trialing"
      return :active if sub.active?
      return :past_due_grace if past_due_grace_active?
      return :past_due if sub.status == "past_due"
      return :paused if sub.status == "paused" || sub.paused?
      return :unpaid if sub.status == "unpaid"
      return :incomplete if sub.status == "incomplete"
      return :incomplete_expired if sub.status == "incomplete_expired"
      return :canceled if sub.canceled? || sub.status == "canceled"
    end

    return :trialing if trial_active?

    :expired
  end

  private

  # A cancel that failed because Stripe already ended the subscription (a
  # missed webhook left it stored as billable) is not a failure: Stripe's own
  # terminal status is recorded locally. "No such subscription" is not proof:
  # Stripe says the same to a key for the wrong mode or account, while the
  # real subscription keeps charging. That, and Stripe not answering, keep
  # blocking for an operator to resolve.
  def ended_at_stripe!(sub)
    return false unless sub.is_a?(Pay::Stripe::Subscription)

    remote = ::Stripe::Subscription.retrieve({ id: sub.processor_id }, { stripe_account: sub.stripe_account }.compact)
    return false unless TERMINAL_SUBSCRIPTION_STATUSES.include?(remote.status)

    ended_at = remote.respond_to?(:ended_at) && remote.ended_at ? Time.at(remote.ended_at) : Time.current
    sub.update!(status: remote.status, ends_at: sub.ends_at || ended_at)
    true
  rescue StandardError
    false
  end

  def current_subscription
    payment_processor&.subscription || pay_subscriptions.order(created_at: :desc).first
  end

  def cleanup_pay_customers
    pay_customers.each do |customer|
      customer.destroy
    rescue StandardError => e
      Rails.logger.warn "[Pay] Unable to clean up customer #{customer.id}: #{e.message}"
    end
  end
end
