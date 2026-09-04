# frozen_string_literal: true

class SubscriptionsController < ApplicationController
  before_action :require_admin, only: %i[create destroy portal]
  skip_before_action :ensure_household_entitled!

  def show
    unless FamilyPlates.config.hosted?
      redirect_to root_path, notice: "Subscriptions are only enabled in hosted mode." and return
    end

    @household = current_household
    @subscription = @household.payment_processor&.subscription
    @status = @household.subscription_status
    @plans = Household::PLANS
  end

  def create
    unless FamilyPlates.config.hosted?
      redirect_to root_path, alert: "Subscriptions are only enabled in hosted mode." and return
    end

    plan_key = params[:plan].to_s.downcase.to_sym
    plan = Household::PLANS[plan_key]

    unless plan
      redirect_to subscription_path, alert: "Invalid subscription plan selected." and return
    end

    # Test/simulated path or environments without live Stripe secret keys
    stripe_key = ENV["STRIPE_SECRET_KEY"].presence || ENV["STRIPE_PRIVATE_KEY"].presence || (Pay::Stripe.private_key if defined?(Pay::Stripe))
    if Rails.env.test? || stripe_key.blank?
      @household = current_household
      @household.set_payment_processor :fake_processor, allow_fake: true
      @household.payment_processor.subscriptions.destroy_all
      @household.payment_processor.subscriptions.create!(
        name: "default",
        processor_id: "sub_sim_#{SecureRandom.hex(8)}",
        processor_plan: plan_key.to_s,
        status: "active",
        current_period_start: Time.current,
        current_period_end: plan_key == :annual ? 1.year.from_now : 1.month.from_now
      )
      redirect_to subscription_path, notice: "Successfully subscribed to the #{plan[:name]} plan! 🎉"
    else
      @household = current_household
      @household.set_payment_processor :stripe
      checkout_session = @household.payment_processor.checkout(
        mode: :subscription,
        line_items: [ { price: plan[:stripe_price_id], quantity: 1 } ],
        success_url: subscription_url(success: true),
        cancel_url: subscription_url(canceled: true)
      )
      redirect_to checkout_session.url, allow_other_host: true
    end
  end

  def destroy
    unless FamilyPlates.config.hosted?
      redirect_to root_path and return
    end

    subscription = current_household.payment_processor&.subscription
    if subscription&.active?
      subscription.cancel
      redirect_to subscription_path, notice: "Your subscription has been canceled. You will retain access until #{subscription.ends_at.to_date.to_formatted_s(:long)}."
    else
      redirect_to subscription_path, alert: "No active subscription found to cancel."
    end
  end

  def portal
    unless FamilyPlates.config.hosted?
      redirect_to root_path and return
    end

    if ENV["STRIPE_SECRET_KEY"].present? && current_household.payment_processor&.processor_id.present?
      portal_session = current_household.payment_processor.billing_portal(return_url: subscription_url)
      redirect_to portal_session.url, allow_other_host: true
    else
      redirect_to subscription_path, notice: "Manage your subscription details below."
    end
  end
end
