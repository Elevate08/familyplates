# frozen_string_literal: true

require "net/smtp"

# A billing owner's agreement to a paid, automatically renewing plan: who
# agreed, for which household, the disclosure they saw word for word, and the
# price Checkout was asked to charge. Stripe collects the card; nothing here
# is card data.
#
# Recorded before Stripe is asked for anything, which also reserves the
# household's one Checkout attempt. Confirmed once Stripe reports the
# subscription that Checkout started as active, and only then is the
# acknowledgment email due. A Checkout the owner abandons stays unconfirmed
# and sends nothing.
#
# Where the Checkout attempt stands (checkout_state):
# - "reserved": the request is asking Stripe for a session.
# - "open": Stripe returned a session, which can still complete.
# - "unknown": the request ended without learning whether Stripe created a
#   session. It keeps the household's reservation until Stripe is asked.
# - "expired": Stripe reports the session expired, or has no session for it.
# - "completed": Stripe reports the session complete and the subscription it
#   started is recorded here, not yet active. That subscription holds the
#   household from then on, until Stripe ends it.
# - "confirmed": the subscription it started is active.
# A household holds at most one reserved, open or unknown attempt, enforced
# by index_billing_consents_on_household_id_open_checkout. An attempt stops
# holding the household only on what Stripe reports, never because time
# passed: a session past its deadline may still have completed.
class BillingConsent < ApplicationRecord
  HELD_CHECKOUT_STATES = %w[reserved open unknown].freeze

  # Every session is created to expire within CHECKOUT_LIFETIME, so by
  # CHECKOUT_HOLD Stripe has settled it one way or the other, and recovery
  # asks Stripe which.
  CHECKOUT_LIFETIME = 23.hours
  CHECKOUT_HOLD = 24.hours
  # Long enough for any request to Stripe, including its network retries, to
  # have finished. A reserved attempt older than this lost its request.
  CHECKOUT_SETTLE_TIME = 10.minutes

  # A send claimed this long ago and never marked sent lost its worker. The
  # message may have been accepted, so it is held for an operator, not resent.
  ACKNOWLEDGMENT_CLAIM_TIMEOUT = 15.minutes
  ACKNOWLEDGMENT_MAX_ATTEMPTS = 5
  ACKNOWLEDGMENT_BACKOFF = [ 1.minute, 5.minutes, 30.minutes, 2.hours ].freeze


  # Stripe answered and refused: no session exists.
  class CheckoutRejected < StandardError; end
  # Stripe may or may not have created a session.
  class CheckoutOutcomeUnknown < StandardError; end

  attribute :id, default: -> { SecureRandom.uuid }

  # Optional, and without foreign keys: the evidence outlives the household
  # and the user it names.
  belongs_to :household, optional: true
  belongs_to :user, optional: true

  validates :user_id, :household_id, :terms_version, :disclosure, :disclosure_digest, :plan_key,
    :currency, :amount_minor_units, :interval, :accepted_at, presence: true
  validates :checkout_session_id, uniqueness: true, allow_nil: true

  scope :confirmed, -> { where.not(confirmed_at: nil) }
  scope :unacknowledged, -> { confirmed.where(acknowledgment_sent_at: nil) }
  scope :held_checkouts, -> { where(confirmed_at: nil, checkout_state: HELD_CHECKOUT_STATES) }
  # Unsent and not waiting on an operator.
  scope :acknowledgment_pending, -> { unacknowledged.where(acknowledgment_uncertain_at: nil, acknowledgment_failed_at: nil) }
  scope :acknowledgment_due, ->(now = Time.current) {
    acknowledgment_pending.where(acknowledgment_claimed_at: nil)
      .where("acknowledgment_next_attempt_at IS NULL OR acknowledgment_next_attempt_at <= ?", now)
  }
  scope :acknowledgment_uncertain, -> { unacknowledged.where.not(acknowledgment_uncertain_at: nil) }
  scope :acknowledgment_failed, -> { unacknowledged.where(acknowledgment_uncertain_at: nil).where.not(acknowledgment_failed_at: nil) }

  def self.record!(offer, household:, user:)
    create!(
      household_id: household.id, user_id: user.id, accepted_at: Time.current, checkout_state: "reserved",
      terms_version: Legal::TERMS_VERSION, disclosure: offer.disclosure, disclosure_digest: offer.digest,
      plan_key: offer.plan_key.to_s, stripe_price_id: offer.stripe_price_id,
      currency: offer.currency, amount_minor_units: offer.amount_minor_units, interval: offer.interval
    )
  end

  # Records the consent and reserves the household's Checkout attempt in one
  # insert, before any request to Stripe. Returns nil while another attempt
  # holds the household (the unique index decides between racing requests)
  # or while the household has a subscription Stripe can still bill. Both
  # are checked under the household lock that confirming an attempt also
  # takes, so a webhook that hands the hold to a subscription mid-request
  # cannot leave a gap a second Checkout fits through.
  def self.reserve(offer, household:, user:)
    with_household_lock(household.id) do
      next if billable_subscription?(household)

      record!(offer, household: household, user: user)
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  # Active, trialing, past due, unpaid, paused, or incomplete while its first
  # payment is pending: anything but a subscription Stripe has ended.
  def self.billable_subscription?(household)
    household.pay_subscriptions.where.not(status: Household::Billing::TERMINAL_SUBSCRIPTION_STATUSES).exists?
  end

  def self.held_checkout(household_id)
    held_checkouts.find_by(household_id: household_id)
  end

  # Serializes a household's reservation with whatever hands its hold to a
  # subscription: a row lock where the database has them, and on SQLite the
  # write transaction, which SQLite runs one at a time.
  def self.with_household_lock(household_id)
    transaction(requires_new: true) do
      Household.lock.where(id: household_id).pick(:id)
      yield
    end
  end

  # Runs after every Pay subscription save: the return from Checkout, the
  # checkout.session.completed and customer.subscription.* webhooks, and
  # replays of any of them, in whatever order they arrive. The first save
  # that finds the subscription active confirms the consent; every later one
  # finds it confirmed.
  def self.confirm_subscription(subscription)
    return unless subscription.status == "active"

    consent_id = consent_id_for(subscription)
    consent = consent_id && find_by(id: consent_id)
    consent&.confirm!(subscription)
  end

  # Checkout copies subscription_data.metadata onto the Stripe subscription,
  # and Pay copies that onto its own record.
  def self.consent_id_for(subscription)
    metadata = subscription.metadata
    metadata = metadata.to_h if !metadata.is_a?(Hash) && metadata.respond_to?(:to_h)
    return unless metadata.is_a?(Hash)

    (metadata["billing_consent_id"] || metadata[:billing_consent_id]).presence
  end

  # The checkout.session.completed and .expired webhooks, and the return from
  # Checkout, carry the session this consent's metadata names. That settles
  # an attempt whose request never learned the session id.
  def self.resolve_checkout_session(session)
    consent_id = session[:metadata] && session[:metadata][:billing_consent_id]
    consent = consent_id.present? && find_by(id: consent_id)
    return unless consent

    customer = session[:customer]
    customer = customer[:id] if customer.respond_to?(:[]) && !customer.is_a?(String)
    return if customer.blank? || customer != consent.stripe_customer_id

    consent.record_checkout_session!(session[:id])
    consent.expire_checkout!("Stripe reports the Checkout session expired") if session[:status] == "expired"
    consent
  end

  # The recurring BillingConsentRecoveryJob. Settles Checkout attempts whose
  # outcome was lost, and any attempt past CHECKOUT_HOLD, by asking Stripe;
  # holds sends whose worker vanished for an operator; and sends every
  # acknowledgment that is due, including ones whose job was never queued.
  # Returns and logs what it found.
  def self.recover!(now: Time.current)
    summary = Hash.new(0)
    held_checkouts.where(checkout_state: "unknown")
      .or(held_checkouts.where(checkout_state: "reserved", accepted_at: ...(now - CHECKOUT_SETTLE_TIME)))
      .or(held_checkouts.where(accepted_at: ...(now - CHECKOUT_HOLD)))
      .find_each { |consent| summary[:reconciled_checkouts] += 1 if consent.reconcile_checkout! }
    acknowledgment_pending.where(acknowledgment_claimed_at: ...(now - ACKNOWLEDGMENT_CLAIM_TIMEOUT)).find_each do |consent|
      consent.mark_acknowledgment_uncertain!("Claimed at #{consent.acknowledgment_claimed_at.utc.iso8601} and never marked sent; the worker was lost")
      summary[:uncertain_acknowledgments] += 1
    end
    acknowledgment_due(now).find_each do |consent|
      summary[:sent_acknowledgments] += 1 if consent.deliver_acknowledgment
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { billing_consent_id: consent.id })
    end
    summary[:awaiting_operator] = acknowledgment_uncertain.count + acknowledgment_failed.count

    if summary.values.any?(&:positive?)
      Rails.logger.warn("[BillingConsent] recovery: #{summary.map { |key, count| "#{key}=#{count}" }.join(" ")}")
    end
    ActiveSupport::Notifications.instrument("recovery.billing_consent", summary)
    summary
  end

  # For an operator once mail is working again:
  #   bin/rails runner "BillingConsent.retry_unsent_acknowledgments"
  # Queues every acknowledgment that never went out, including ones that ran
  # out of attempts. Leaves alone a send that may have been delivered; see
  # #resolve_uncertain_acknowledgment!.
  def self.retry_unsent_acknowledgments
    now = Time.current
    unacknowledged.where(acknowledgment_uncertain_at: nil, acknowledgment_claimed_at: nil).where.not(acknowledgment_failed_at: nil)
      .update_all(acknowledgment_failed_at: nil, acknowledgment_attempts: 0, acknowledgment_next_attempt_at: now, updated_at: now)
    acknowledgment_pending.where(acknowledgment_claimed_at: nil).find_each.count { |consent| consent.enqueue_acknowledgment }
  end

  def confirmed?
    confirmed_at.present?
  end

  def acknowledged?
    acknowledgment_sent_at.present?
  end

  def acknowledgment_uncertain?
    acknowledgment_uncertain_at.present? && !acknowledged?
  end

  def plan_name
    Household::PLANS.dig(plan_key.to_sym, :name) || plan_key.titleize
  end

  # What this consent agreed to pay, from the record rather than today's plans.
  def price_label
    "#{BillingOffer.format_money(amount_minor_units, currency)} per #{interval}"
  end

  # What Stripe reports was actually charged, after any discount.
  def paid_label
    money(paid_amount_minor_units, paid_currency) if paid_amount_minor_units
  end

  def paid_discount_label
    money(paid_discount_minor_units, paid_currency) if paid_discount_minor_units.to_i.positive?
  end

  def stripe_customer_id
    Pay::Customer.where(owner_type: "Household", owner_id: household_id, processor: "stripe")
      .order(updated_at: :desc).pick(:processor_id)
  end

  # Stripe replays a request with the same key instead of running it twice,
  # including stripe-ruby's own network retries. One consent is one attempt.
  def checkout_idempotency_key
    "familyplates-billing-consent-#{id}-checkout"
  end

  # Asks Stripe for this consent's Checkout session. A refusal discards the
  # reservation; a lost answer keeps it as "unknown", so no second session
  # can be requested until Stripe has been asked what happened.
  def create_checkout_session!(params)
    session = ::Stripe::Checkout::Session.create(params, { idempotency_key: checkout_idempotency_key })
  rescue StandardError => e
    if checkout_rejected?(e)
      discard_unstarted_checkout!("#{e.class}: #{e.message}")
      raise CheckoutRejected, e.message
    end

    mark_checkout_unknown!(e)
    raise CheckoutOutcomeUnknown, e.message
  else
    begin
      record_checkout_session!(session.id)
    rescue StandardError => e
      # Stripe made the session; the row stays reserved and recover! finds it.
      Rails.error.report(e, handled: true, context: { billing_consent_id: id, checkout_session_id: session.id })
      raise CheckoutOutcomeUnknown, e.message
    end
    session
  end

  # Nothing was asked of Stripe, or Stripe refused, so no session exists and
  # nothing can ever confirm this consent.
  def discard_unstarted_checkout!(reason)
    Rails.logger.warn("[BillingConsent] #{id} Checkout not started: #{reason}")
    self.class.where(id: id, checkout_state: "reserved", confirmed_at: nil).delete_all
  end

  def mark_checkout_unknown!(error)
    message = "#{error.class}: #{error.message}".truncate(255)
    self.class.where(id: id, checkout_state: "reserved").update_all(checkout_state: "unknown", checkout_error: message, updated_at: Time.current)
    Rails.logger.error("[BillingConsent] #{id} Checkout outcome unknown, holding the household until Stripe is checked: #{message}")
    Rails.error.report(error, handled: true, context: { billing_consent_id: id, household_id: household_id })
  end

  # A session id is only ever filled in, never replaced. An attempt that was
  # still reserved or unknown now knows its session is open.
  def record_checkout_session!(session_id)
    now = Time.current
    self.class.where(id: id, checkout_session_id: nil, confirmed_at: nil, checkout_state: %w[reserved unknown])
      .update_all(checkout_session_id: session_id, checkout_state: "open", checkout_error: nil, updated_at: now)
    self.class.where(id: id, checkout_session_id: nil).update_all(checkout_session_id: session_id, updated_at: now)
    reload
  end

  def expire_checkout!(reason)
    self.class.held_checkouts.where(id: id).update_all(checkout_state: "expired", checkout_error: reason.truncate(255), updated_at: Time.current)
  end

  # Settles a held attempt by asking Stripe about the session this consent
  # names: by its id once known, otherwise by its metadata among the
  # customer's sessions. Never creates a session, and never releases the
  # household on the clock alone. A complete session is synced, so the
  # subscription it started blocks another Checkout; an expired one, or none
  # at all once a lost request has settled, frees the household. Anything
  # Stripe cannot answer, or answers ambiguously, keeps the hold. Returns
  # whether the attempt was settled.
  #
  # supersede: the billing owner is starting a new Checkout, so a session of
  # theirs that is still open is expired on Stripe and the household freed.
  # Once Stripe has expired a session it can no longer be paid; if Stripe
  # refuses (it was paid a moment ago), the hold stays. Recovery never
  # supersedes: only the owner's own new attempt retires the old one.
  def reconcile_checkout!(supersede: false)
    return false unless confirmed_at.nil? && HELD_CHECKOUT_STATES.include?(checkout_state)
    return false if checkout_state == "reserved" && accepted_at >= CHECKOUT_SETTLE_TIME.ago

    customer_id = stripe_customer_id
    if customer_id.blank?
      Rails.logger.warn("[BillingConsent] #{id} Checkout still held: the household has no Stripe customer to ask about it")
      return false
    end

    session = checkout_session_id ? retrieve_checkout_session(customer_id) : find_checkout_session(customer_id)
    case session && session[:status]
    when "complete"
      settle_completed_checkout!(session)
    when "expired"
      record_checkout_session!(session[:id])
      expire_checkout!("Stripe reports the Checkout session expired")
      true
    when "open"
      record_checkout_session!(session[:id])
      return true unless supersede

      ::Stripe::Checkout::Session.expire(session[:id])
      expire_checkout!("Superseded by a new Checkout; session expired on Stripe")
      true
    when nil
      return false unless session.nil? && checkout_session_id.nil? && accepted_at < CHECKOUT_SETTLE_TIME.ago

      expire_checkout!("Stripe has no Checkout session for this consent")
      true
    else
      Rails.logger.warn("[BillingConsent] #{id} Checkout still held: Stripe reports session #{session[:id]} as #{session[:status].inspect}")
      false
    end
  rescue ::Stripe::StripeError, Pay::Error => e
    Rails.logger.warn("[BillingConsent] #{id} Checkout still held, Stripe lookup failed: #{e.class}: #{e.message}")
    false
  end

  def confirm!(subscription)
    return if confirmed?

    unless matches?(subscription)
      Rails.logger.error("[BillingConsent] #{id} not confirmed: subscription #{subscription.processor_id} " \
        "is not the household's subscription at the agreed price")
      return
    end

    now = Time.current
    claimed = self.class.with_household_lock(household_id) do
      self.class.where(id: id, confirmed_at: nil).update_all(
        confirmed_at: now, checkout_state: "confirmed", pay_subscription_id: subscription.id,
        subscription_processor_id: subscription.processor_id, acknowledgment_next_attempt_at: now, updated_at: now
      ).tap do |count|
        # Paid service starts now, so any free trial left ends now too.
        household&.end_trial_for_paid_start!(now) if count == 1
      end
    end
    enqueue_acknowledgment if claimed == 1
  end

  # The row already says the acknowledgment is due, so a queue that refuses
  # the job only delays it until BillingConsentRecoveryJob runs.
  def enqueue_acknowledgment
    return true if BillingConsentAcknowledgmentJob.perform_later(id)

    raise ActiveJob::EnqueueError, "BillingConsentAcknowledgmentJob for #{id} was not enqueued"
  rescue StandardError => e
    Rails.logger.error("[BillingConsent] #{id} acknowledgment not queued, left due for recovery: #{e.class}: #{e.message}")
    Rails.error.report(e, handled: true, context: { billing_consent_id: id })
    false
  end

  # Sends the acknowledgment, never twice. Everything that can fail without
  # sending (the payment lookup, rendering, connecting) is retried on a
  # schedule. A send that fails in a way that may follow the mail server
  # accepting the message is held for an operator instead, as is one whose
  # worker vanished mid-send; SMTP gives no way to know whether it arrived.
  # Returns whether this call sent it.
  def deliver_acknowledgment
    return false unless self.class.acknowledgment_pending.where(id: id, acknowledgment_claimed_at: nil).exists?

    delivery = prepare_acknowledgment
    return false unless delivery

    claimed_at = claim_acknowledgment
    return false unless claimed_at

    begin
      delivery.deliver_now
    rescue *ApplicationMailer::NOT_SENT_ERRORS => e
      schedule_acknowledgment_retry!(e, claimed_at: claimed_at)
      return false
    rescue StandardError => e
      mark_acknowledgment_uncertain!(e)
      return false
    end

    now = Time.current
    self.class.where(id: id).update_all(acknowledgment_sent_at: now, acknowledgment_next_attempt_at: nil,
      acknowledgment_last_error: nil, updated_at: now)
    true
  end

  # Holds a send that may have gone out. Never cleared automatically.
  def mark_acknowledgment_uncertain!(error)
    message = (error.is_a?(Exception) ? "#{error.class}: #{error.message}" : error.to_s).truncate(255)
    now = Time.current
    marked = self.class.unacknowledged.where(id: id, acknowledgment_uncertain_at: nil)
      .update_all(acknowledgment_uncertain_at: now, acknowledgment_next_attempt_at: nil, acknowledgment_last_error: message, updated_at: now)
    return if marked.zero?

    Rails.logger.error("[BillingConsent] #{id} acknowledgment may or may not have been delivered; not resending. " \
      "Check the mail provider, then resolve_uncertain_acknowledgment!: #{message}")
    Rails.error.report(error.is_a?(Exception) ? error : RuntimeError.new(message), handled: true,
      context: { billing_consent_id: id, acknowledgment: "uncertain" })
  end

  # For an operator who has checked the mail provider's log:
  #   BillingConsent.find(id).resolve_uncertain_acknowledgment!(delivered: true)
  # records that it went out;
  #   BillingConsent.find(id).resolve_uncertain_acknowledgment!(delivered: false)
  # sends it again.
  def resolve_uncertain_acknowledgment!(delivered:)
    raise ArgumentError, "acknowledgment #{id} is not uncertain" unless reload.acknowledgment_uncertain?

    now = Time.current
    if delivered
      update_columns(acknowledgment_sent_at: acknowledgment_claimed_at || acknowledgment_uncertain_at,
        acknowledgment_last_error: nil, updated_at: now)
    else
      update_columns(acknowledgment_uncertain_at: nil, acknowledgment_claimed_at: nil, acknowledgment_failed_at: nil,
        acknowledgment_attempts: 0, acknowledgment_next_attempt_at: now, updated_at: now)
      enqueue_acknowledgment
    end
  end

  private

  def money(minor_units, money_currency)
    BillingOffer.format_money(minor_units, money_currency)
  end

  # Stripe refused the request outright. A 409 (a request with the same key
  # still running), an idempotency mismatch, a 5xx or no answer at all means
  # a session may exist.
  def checkout_rejected?(error)
    error.is_a?(::Stripe::StripeError) && !error.is_a?(::Stripe::IdempotencyError) &&
      error.http_status.is_a?(Integer) && error.http_status.between?(400, 499) && error.http_status != 409
  end

  # Every page, so not finding the session means Stripe has none.
  def find_checkout_session(customer_id)
    params = { customer: customer_id, created: { gte: (accepted_at - 5.minutes).to_i }, limit: 100 }
    loop do
      page = ::Stripe::Checkout::Session.list(params)
      found = page.data.find { |session| names_this_consent?(session, customer_id) }
      return found if found || !page[:has_more] || page.data.empty?

      params = params.merge(starting_after: page.data.last[:id])
    end
  end

  # Nil unless the session is this consent's, for this household's customer.
  def retrieve_checkout_session(customer_id)
    session = ::Stripe::Checkout::Session.retrieve(checkout_session_id)
    return session if names_this_consent?(session, customer_id)

    Rails.logger.warn("[BillingConsent] #{id} Checkout still held: session #{checkout_session_id} does not name this consent and customer")
    nil
  end

  def names_this_consent?(session, customer_id)
    customer = session[:customer]
    customer = customer[:id] if customer.respond_to?(:[]) && !customer.is_a?(String)
    session[:metadata] && session[:metadata][:billing_consent_id] == id && customer == customer_id
  end

  # Syncs the subscription a complete session started. Active, it confirms
  # this consent through the subscription hook. Not active yet, the
  # subscription now recorded here takes over the household's hold, under
  # the lock reserve takes. Not recorded, Stripe's answer is incomplete and
  # the attempt stays held.
  def settle_completed_checkout!(session)
    record_checkout_session!(session[:id])
    Pay::Stripe.sync_checkout_session(session[:id])
    return true if reload.confirmed?

    subscription_id = session[:subscription]
    subscription_id = subscription_id[:id] if subscription_id.respond_to?(:[]) && !subscription_id.is_a?(String)
    subscription = subscription_id.present? && Pay::Subscription.joins(:customer)
      .find_by(processor_id: subscription_id, pay_customers: { owner_type: "Household", owner_id: household_id })
    unless subscription
      Rails.logger.warn("[BillingConsent] #{id} Checkout session #{session[:id]} is complete but its subscription " \
        "is not recorded yet; still held")
      return false
    end

    self.class.with_household_lock(household_id) do
      self.class.held_checkouts.where(id: id).update_all(checkout_state: "completed",
        checkout_error: "Checkout completed; subscription #{subscription.processor_id} is #{subscription.status}".truncate(255),
        updated_at: Time.current)
    end
    true
  end

  # The payment details and the rendered message, or nil after scheduling a
  # retry. Nothing has been sent by then.
  def prepare_acknowledgment
    if user.nil?
      fail_acknowledgment!("No user to acknowledge")
      return
    end

    unless paid_amount_minor_units
      update_columns(BillingConsent::PaymentDetails.fetch(self).merge(updated_at: Time.current))
    end
    delivery = BillingConsentMailer.acknowledgment(self)
    delivery.message
    delivery
  rescue StandardError => e
    schedule_acknowledgment_retry!(e)
    nil
  end

  def claim_acknowledgment
    now = Time.current
    claimed = self.class.acknowledgment_pending.where(id: id, acknowledgment_claimed_at: nil).update_all(
      [ "acknowledgment_claimed_at = ?, acknowledgment_attempts = acknowledgment_attempts + 1, updated_at = ?", now, now ]
    )
    now if claimed == 1
  end

  # Gives up a claim, or never took one, after an error that sent nothing,
  # and sets when to try again. Out of attempts, it waits for an operator.
  def schedule_acknowledgment_retry!(error, claimed_at: nil)
    attempts = self.class.where(id: id).pick(:acknowledgment_attempts).to_i + (claimed_at ? 0 : 1)
    now = Time.current
    message = "#{error.class}: #{error.message}".truncate(255)
    changes = { acknowledgment_attempts: attempts, acknowledgment_last_error: message, acknowledgment_claimed_at: nil, updated_at: now }
    if attempts >= ACKNOWLEDGMENT_MAX_ATTEMPTS
      changes.merge!(acknowledgment_failed_at: now, acknowledgment_next_attempt_at: nil)
    else
      changes[:acknowledgment_next_attempt_at] = now + ACKNOWLEDGMENT_BACKOFF.fetch(attempts - 1, ACKNOWLEDGMENT_BACKOFF.last)
    end

    scope = self.class.unacknowledged.where(id: id, acknowledgment_uncertain_at: nil)
    scope = claimed_at ? scope.where.not(acknowledgment_claimed_at: nil) : scope.where(acknowledgment_claimed_at: nil)
    scope.update_all(changes)
    Rails.logger.warn("[BillingConsent] #{id} acknowledgment not sent (attempt #{attempts}): #{message}")
    Rails.error.report(error, handled: true, context: { billing_consent_id: id, attempts: attempts }) if changes[:acknowledgment_failed_at]
  end

  def fail_acknowledgment!(reason)
    now = Time.current
    self.class.unacknowledged.where(id: id).update_all(acknowledgment_failed_at: now, acknowledgment_next_attempt_at: nil,
      acknowledgment_last_error: reason, updated_at: now)
    Rails.logger.error("[BillingConsent] #{id} acknowledgment failed: #{reason}")
    Rails.error.report(RuntimeError.new(reason), handled: true, context: { billing_consent_id: id })
  end

  # The subscription belongs to this household's Pay customer and charges
  # the Price this consent agreed to. Its metadata naming this consent is
  # what ties it to this consent's Checkout, which also covers an attempt
  # whose session id was never recorded.
  def matches?(subscription)
    customer = subscription.customer
    customer.present? && customer.owner_type == "Household" && customer.owner_id.to_s == household_id &&
      (stripe_price_id.blank? || subscription.processor_plan == stripe_price_id)
  end
end
