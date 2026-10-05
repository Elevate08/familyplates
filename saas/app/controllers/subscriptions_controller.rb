# frozen_string_literal: true

class SubscriptionsController < ApplicationController
  BILLING_OWNER_DENIAL = "Access restricted to the household's billing owner."
  CHECKOUT_UNAVAILABLE = "Checkout could not be started, so you have not been charged. Please try again later or contact support."
  CHECKOUT_IN_PROGRESS = "A subscription is already active or Checkout is still in progress for this household."
  CHECKOUT_OUTCOME_UNKNOWN = "We could not confirm with Stripe whether Checkout started. To avoid charging you twice, " \
    "subscribing is paused while we check. If a payment went through, your subscription will appear here; " \
    "otherwise you can subscribe again shortly."

  before_action :require_billing_owner, only: %i[create portal]
  before_action :require_cancellation_authority, only: :destroy
  skip_before_action :ensure_household_entitled!
  # Seeing and canceling a subscription stay open to someone who has yet to
  # accept changed Terms. Starting one does not: its consent cites the Terms.
  allow_without_current_terms only: %i[show destroy portal]
  helper_method :billing_owner_hint, :cancellable?

  def show
    unless FamilyPlates.config.hosted?
      redirect_to root_path, notice: "Subscriptions are only enabled in hosted mode." and return
    end

    @household = current_household
    sync_returning_checkout
    note_abandoned_checkout
    @subscription = @household.payment_processor&.subscription
    @status = @household.subscription_status
    @offers = Household::PLANS.keys.index_with { |key| BillingOffer.for(key) }
  end

  def create
    unless FamilyPlates.config.hosted?
      redirect_to root_path, alert: "Subscriptions are only enabled in hosted mode." and return
    end

    offer = BillingOffer.for(params[:plan])

    unless offer
      redirect_to subscription_path, alert: "Invalid subscription plan selected." and return
    end

    if !simulate_checkout? && stripe_secret_key.blank?
      redirect_to subscription_path, alert: "Billing is not available right now." and return
    end

    if (problem = billing_consent_problem(offer))
      redirect_to subscription_path, alert: problem and return
    end

    consent = reserve_checkout(offer)
    unless consent
      unknown = BillingConsent.held_checkout(current_household.id)&.checkout_state == "unknown"
      redirect_to subscription_path, alert: unknown ? CHECKOUT_OUTCOME_UNKNOWN : CHECKOUT_IN_PROGRESS and return
    end

    if simulate_checkout?
      subscribe_with_fake_processor(offer, consent)
    else
      redirect_to_stripe_checkout(offer, consent)
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
    elsif cancellable?(subscription)
      # Past due, unpaid, paused or incomplete: Stripe may still be retrying a
      # payment and there is no paid term left to keep, so it stops now.
      subscription.cancel_now!
      redirect_to subscription_path, notice: "Your subscription has been canceled. You will not be charged again."
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

  # Billing follows the signed-in user, not the selected profile: an admin
  # profile can be picked by anyone at a shared screen, and a kiosk session
  # belongs to whoever paired it (household_billing_owner_session?). The
  # appliance has no billing, so it keeps the organizer check and each action
  # sends it home.
  def require_billing_owner
    require_billing_authority { household_billing_owner_session? }
  end

  def require_cancellation_authority
    require_billing_authority { household_cancellation_session? }
  end

  def require_billing_authority
    return require_admin unless FamilyPlates.config.hosted?
    return if deny_kiosk_access

    deny_access(BILLING_OWNER_DENIAL) unless yield
  end

  # A subscription Stripe could still bill and nobody has cancelled yet.
  def cancellable?(subscription)
    subscription.present? && !subscription.canceled? &&
      Household::Billing::TERMINAL_SUBSCRIPTION_STATUSES.exclude?(subscription.status)
  end

  def billing_owner_hint
    if current_household&.billing_owner_user_id.nil?
      "This household has no billing owner yet. Contact support to set one."
    else
      "Only the household's billing owner can subscribe."
    end
  end

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
    session = household_checkout_session(session_id)
    return unless session

    BillingConsent.resolve_checkout_session(session)
    Pay::Stripe.sync_checkout_session(session_id)
    if @household.reload.active_subscription?
      flash.now[:notice] = "Thank you for subscribing! Your kitchen is now fully activated. 🎉"
    end
  rescue StandardError => e
    Rails.logger.warn("Could not sync checkout session #{session_id}: #{e.class}: #{e.message}")
  end

  def household_checkout_session(session_id)
    customer_id = @household.payment_processor&.processor_id
    return if customer_id.blank?

    session = ::Stripe::Checkout::Session.retrieve(session_id)
    session if BillingConsent.session_customer_id(session) == customer_id
  rescue ::Stripe::StripeError => e
    Rails.logger.warn("Rejected checkout session #{session_id} for household #{@household.id}: #{e.class}: #{e.message}")
    nil
  end

  # Pay sends both Checkout return URLs back with the session id, so the
  # cancel return is told apart by its flag. Nothing was charged: Checkout
  # never completed, and the consent it started stays unconfirmed.
  def note_abandoned_checkout
    return unless params[:canceled].present?
    return if @household.reload.active_subscription?

    flash.now[:notice] = "Checkout was not completed. You have not been charged and no subscription was started."
  end

  # The billing owner ticked the box beside this offer's terms, on a page
  # rendered for them, for this household, within the last half hour, and
  # nothing they agreed to has changed since.
  def billing_consent_problem(offer)
    unless params[:accept_renewal_terms] == "1"
      return "Please review the subscription terms and tick the box to agree before subscribing."
    end
    return if offer.accepted_token?(params[:offer_token], household: current_household, user: current_user)

    "The subscription terms have changed or this page has expired. Please review the terms below and agree again."
  end

  # Records the consent and reserves the household's one Checkout attempt
  # before anything is asked of Stripe, so two racing requests cannot both
  # start one. Nil while the household has a subscription Stripe can still
  # bill (active, trialing, past due, unpaid, paused, or incomplete while its
  # first payment is pending) or another attempt can still complete. A held
  # attempt is checked with Stripe first, which frees the household once
  # Stripe confirms its session expired or never existed, or once the
  # person's own still-open session is expired there because they chose
  # again. A session Stripe reports complete is synced instead, and the
  # second reservation, which checks for a billable subscription again under
  # the household lock, refuses because of the subscription that sync
  # recorded.
  def reserve_checkout(offer)
    household = current_household
    return if household.active_subscription?
    return if BillingConsent.billable_subscription?(household)

    reserve = -> { BillingConsent.reserve(offer, household: household, user: current_user) }
    reserved = reserve.call
    return reserved if reserved

    # Only a Checkout this person started is theirs to retire; one started by
    # a previous billing owner is left to finish or expire on its own.
    held = BillingConsent.held_checkout(household.id)
    held&.reconcile_checkout!(supersede: held.user_id == current_user.id) && reserve.call
  end

  def stripe_secret_key
    ENV["STRIPE_SECRET_KEY"].presence ||
      ENV["STRIPE_PRIVATE_KEY"].presence ||
      (Pay::Stripe.private_key if defined?(Pay::Stripe))
  end

  # Tests, and development with no Stripe secret, never leave the app.
  # Production must not: a missing key used to subscribe the household for free.
  def simulate_checkout?
    return false if Rails.env.production?
    return true if Rails.env.test? && (params[:simulate].present? || ENV["ENABLE_REAL_STRIPE_TESTS"].blank?)

    stripe_secret_key.blank?
  end

  # Same consent and confirmation as Checkout, so the acknowledgment flow runs
  # in development and tests without Stripe.
  def subscribe_with_fake_processor(offer, consent)
    @household = current_household
    consent.record_checkout_session!("cs_sim_#{SecureRandom.hex(8)}")
    @household.set_payment_processor :fake_processor, allow_fake: true
    @household.payment_processor.subscriptions.destroy_all
    @household.payment_processor.subscriptions.create!(
      name: "default",
      processor_id: "sub_sim_#{SecureRandom.hex(8)}",
      processor_plan: offer.stripe_price_id || offer.plan_key.to_s,
      status: "active",
      current_period_start: Time.current,
      current_period_end: offer.interval == "year" ? 1.year.from_now : 1.month.from_now,
      metadata: { "billing_consent_id" => consent.id }
    )
    redirect_to subscription_path, notice: "Successfully subscribed to the #{offer.name} plan! 🎉"
  end

  # The consent, already holding the household's reservation, is named in
  # both the session's and the subscription's metadata, which is how the
  # subscription Stripe later reports finds the consent it came from.
  def redirect_to_stripe_checkout(offer, consent)
    @household = current_household

    session_params = stripe_checkout_params(offer, consent)
    unless session_params
      consent.discard_unstarted_checkout!("Checkout for the #{offer.plan_key} plan was not requested")
      redirect_to subscription_path, alert: CHECKOUT_UNAVAILABLE and return
    end

    checkout_session = consent.create_checkout_session!(session_params)
    redirect_to checkout_session.url, allow_other_host: true
  rescue BillingConsent::CheckoutRejected => e
    Rails.logger.error("[Billing] Stripe refused Checkout for the #{offer.plan_key} plan: #{e.message}")
    redirect_to subscription_path, alert: CHECKOUT_UNAVAILABLE
  rescue BillingConsent::CheckoutOutcomeUnknown
    redirect_to subscription_path, alert: CHECKOUT_OUTCOME_UNKNOWN
  end

  # What Checkout is asked for, or nil when it must not be asked: the
  # configured Price differs from the page, or the Stripe customer could not
  # be set up. Built only from the consent and the offer, so a replay under
  # the same idempotency key sends the same request.
  def stripe_checkout_params(offer, consent)
    unless offer.stripe_price_matches?
      Rails.logger.error("[Billing] Stripe price #{offer.stripe_price_id} does not match the #{offer.plan_key} plan " \
        "(#{offer.amount_minor_units} #{offer.currency} per #{offer.interval}); Checkout not started")
      return
    end

    @household.set_payment_processor :stripe
    customer = @household.payment_processor
    customer.api_record unless customer.processor_id?

    {
      customer: customer.processor_id,
      mode: "subscription",
      line_items: [ offer.checkout_line_item ],
      success_url: checkout_return_url(success: true),
      cancel_url: checkout_return_url(canceled: true),
      expires_at: (consent.accepted_at + BillingConsent::CHECKOUT_LIFETIME).to_i,
      metadata: { billing_consent_id: consent.id },
      **checkout_discount_options(consent)
    }
  rescue ::Stripe::StripeError, Pay::Error => e
    Rails.logger.error("[Billing] Checkout for the #{offer.plan_key} plan not started: #{e.class}: #{e.message}")
    nil
  end

  # Stripe fills in the session id, which sync_returning_checkout reads.
  def checkout_return_url(**flags)
    "#{subscription_url(**flags)}&stripe_checkout_session_id={CHECKOUT_SESSION_ID}"
  end

  # Stripe takes either a discount or a promotion-code box, never both. A
  # household an operator gave a promotion gets it applied; anyone else can
  # type a code. The code rides on the subscription so the console can show
  # it, beside the consent the subscription confirms.
  def checkout_discount_options(consent)
    metadata = { billing_consent_id: consent.id }
    promotion = @household.checkout_promotion
    return { allow_promotion_codes: true, subscription_data: { metadata: metadata } } unless promotion

    {
      discounts: [ { promotion_code: promotion.provider_promotion_code_id } ],
      subscription_data: { metadata: metadata.merge(promotion_code: promotion.code) }
    }
  end
end
