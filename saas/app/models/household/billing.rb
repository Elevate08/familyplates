# Trials, Stripe subscriptions through Pay, and whether a household may use
# the kitchen. Only the hosted edition includes this; an appliance household
# is never billed, so the core never asks.
module Household::Billing
  extend ActiveSupport::Concern

  FREE_TRIAL_DAYS = 14
  PAST_DUE_GRACE_DAYS = 7

  PLANS = {
    monthly: {
      name: "Monthly",
      price: "$4",
      interval: "month",
      stripe_price_id: ENV["STRIPE_MONTHLY_PRICE_ID"].presence || "price_monthly",
      description: "Full family kitchen access, billed monthly"
    },
    annual: {
      name: "Annual",
      price: "$35",
      interval: "year",
      discount: "Save 27%",
      stripe_price_id: ENV["STRIPE_ANNUAL_PRICE_ID"].presence || "price_annual",
      description: "Best value for families, billed once a year"
    }
  }.freeze

  included do
    pay_customer default: true

    # Prepended so it runs ahead of the dependent: destroy/nullify hooks.
    before_destroy :cleanup_pay_customers, prepend: true

    delegate :subscribed?, :on_trial?, :on_trial_or_subscribed?, to: :payment_processor, allow_nil: true

    alias_method :pay_customer_email, :email
  end

  # Cancel now, no refund. Returns subscriptions that failed so an operator can
  # finish them in Stripe. Not named cancel_active_pay_subscriptions!: Pay's
  # pay_customer defines that, without the rescue, and would shadow this.
  def cancel_subscriptions_before_deletion!
    pay_subscriptions.active.reject do |sub|
      sub.cancel_now!
      true
    rescue StandardError => e
      Rails.logger.warn "[Pay] Unable to cancel subscription #{sub.id} (#{sub.processor_id}) during household deletion: #{e.message}"
      false
    end
  end

  def pay_customer_name
    name
  end

  def trial_ends_at
    trial_extended_until || ((created_at || Time.current) + FREE_TRIAL_DAYS.days)
  end

  def trial_active?
    Time.current < trial_ends_at
  end

  def trial_days_left
    [ ((trial_ends_at - Time.current) / 1.day).ceil, 0 ].max
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
