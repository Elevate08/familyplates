# frozen_string_literal: true

class SubscriptionsController < ApplicationController
  before_action :require_admin, only: %i[create destroy portal]
  skip_before_action :ensure_household_entitled!

  def show
    unless FamilyPlates.config.hosted?
      redirect_to root_path, notice: "Subscriptions are only enabled in hosted mode." and return
    end

    @household = current_household
    sync_returning_checkout
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

    if simulate_checkout?
      subscribe_with_fake_processor(plan_key, plan)
    else
      redirect_to_stripe_checkout(plan_key, plan)
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

    if stripe_secret_key.present? && current_household.payment_processor&.processor_id.present?
      portal_session = current_household.payment_processor.billing_portal(return_url: subscription_url)
      redirect_to portal_session.url, allow_other_host: true
    else
      redirect_to subscription_path, notice: "Manage your subscription details below."
    end
  end

  private

  # Stripe sends the customer back with the session Pay appended to the
  # success_url. Syncing it here activates the kitchen on arrival rather than
  # whenever the webhook lands, which the customer would otherwise wait on
  # while looking at the Subscribe buttons they just used. The session id
  # comes from the URL, so the thank-you depends on this household ending up
  # subscribed, not on the sync merely succeeding.
  def sync_returning_checkout
    session_id = params[:stripe_checkout_session_id].presence
    return unless session_id
    # The session id is in the return URL. Anyone who learns it could otherwise
    # make this request pull and apply another household's Checkout session.
    return unless checkout_session_belongs_to_household?(session_id)

    Pay::Stripe.sync_checkout_session(session_id)
    if @household.reload.active_subscription?
      flash.now[:notice] = "Thank you for subscribing! Your kitchen is now fully activated. 🎉"
    end
  rescue StandardError => e
    Rails.logger.warn("Could not sync checkout session #{session_id}: #{e.class}: #{e.message}")
  end

  def checkout_session_belongs_to_household?(session_id)
    customer_id = @household.payment_processor&.processor_id
    return false if customer_id.blank?

    session = ::Stripe::Checkout::Session.retrieve(session_id)
    checkout_customer_id(session) == customer_id
  rescue ::Stripe::StripeError => e
    Rails.logger.warn("Rejected checkout session #{session_id} for household #{@household.id}: #{e.class}: #{e.message}")
    false
  end

  def checkout_customer_id(session)
    customer = session.customer
    customer.respond_to?(:id) && !customer.is_a?(String) ? customer.id : customer.to_s
  end

  def stripe_secret_key
    ENV["STRIPE_SECRET_KEY"].presence ||
      ENV["STRIPE_PRIVATE_KEY"].presence ||
      (Pay::Stripe.private_key if defined?(Pay::Stripe))
  end

  # Test runs, and any environment with no Stripe secret, never leave the app.
  def simulate_checkout?
    (Rails.env.test? && params[:simulate].present?) ||
      (Rails.env.test? && ENV["ENABLE_REAL_STRIPE_TESTS"].blank?) ||
      stripe_secret_key.blank?
  end

  def subscribe_with_fake_processor(plan_key, plan)
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
  end

  def redirect_to_stripe_checkout(plan_key, plan)
    @household = current_household
    @household.set_payment_processor :stripe

    checkout_session = @household.payment_processor.checkout(
      mode: :subscription,
      line_items: checkout_line_items(plan_key, plan),
      success_url: subscription_url(success: true),
      cancel_url: subscription_url(canceled: true),
      **checkout_discount_options
    )
    redirect_to checkout_session.url, allow_other_host: true
  end

  # Stripe takes either a discount or a promotion-code box, never both. A
  # household an operator gave a promotion gets it applied; anyone else can
  # type a code. The code rides on the subscription so the console can show it.
  def checkout_discount_options
    promotion = @household.checkout_promotion
    return { allow_promotion_codes: true } unless promotion

    {
      discounts: [ { promotion_code: promotion.provider_promotion_code_id } ],
      subscription_data: { metadata: { promotion_code: promotion.code } }
    }
  end

  def checkout_line_items(plan_key, plan)
    if ENV["STRIPE_#{plan_key.to_s.upcase}_PRICE_ID"].present?
      [ { price: plan[:stripe_price_id], quantity: 1 } ]
    else
      [
        {
          price_data: {
            currency: "usd",
            unit_amount: plan_key == :annual ? 3500 : 400,
            recurring: { interval: plan_key == :annual ? "year" : "month" },
            product_data: {
              name: "FamilyPlates #{plan[:name]} Plan",
              description: plan[:description]
            }
          },
          quantity: 1
        }
      ]
    end
  end
end
