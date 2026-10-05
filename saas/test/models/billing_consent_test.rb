# frozen_string_literal: true

require "test_helper"

class BillingConsentTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActionMailer::TestHelper
  include BillingConsentTestHelper

  setup do
    @household = households(:one)
    @user = User.create!(email: "owner@consent.test")
    @consent = BillingConsent.record!(BillingOffer.for(:annual), household: @household, user: @user)
    @consent.update!(checkout_session_id: "cs_test_consent", checkout_state: "confirmed", confirmed_at: Time.current,
      acknowledgment_next_attempt_at: Time.current, **verified_payment)
  end

  teardown do
    if BillingConsentMailer.singleton_class.method_defined?(:acknowledgment, false)
      BillingConsentMailer.singleton_class.remove_method(:acknowledgment)
    end
    if BillingConsentAcknowledgmentJob.singleton_class.method_defined?(:perform_later, false)
      BillingConsentAcknowledgmentJob.singleton_class.remove_method(:perform_later)
    end
  end

  # --- Checkout reservation --------------------------------------------------

  test "a household holds one Checkout attempt at a time, enforced by the database" do
    first = BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
    assert_equal "reserved", first.checkout_state

    # The second request lost the race: its insert hit the unique index.
    assert_nil BillingConsent.reserve(BillingOffer.for(:annual), household: @household, user: @user)
    assert_raises(ActiveRecord::RecordNotUnique) do
      BillingConsent.record!(BillingOffer.for(:monthly), household: @household, user: @user)
    end
    assert_equal [ first ], BillingConsent.held_checkouts.where(household_id: @household.id).to_a

    other = BillingConsent.reserve(BillingOffer.for(:monthly), household: households(:two), user: @user)
    assert other, "another household's attempt is independent"
  end

  test "open and unknown attempts keep the hold; expired and confirmed ones release it" do
    held = BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)

    %w[open unknown].each do |state|
      held.update_columns(checkout_state: state)
      assert_nil BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user), state
    end

    held.update_columns(checkout_state: "expired")
    assert BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
  end

  test "an attempt past its hold keeps holding the household until Stripe settles it" do
    held = unknown_attempt
    held.update_columns(accepted_at: (BillingConsent::CHECKOUT_HOLD + 1.minute).ago)

    assert_nil BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user), "the clock alone releases nothing"
    assert_equal "unknown", held.reload.checkout_state
  end

  test "a reservation refuses once a webhook hands the held attempt to a subscription" do
    @household.set_payment_processor :stripe, allow_fake: true, processor_id: "cus_consent"
    held = BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
    held.update_columns(checkout_state: "open", checkout_session_id: "cs_webhook")

    # The webhook's sync saves the subscription, which confirms the attempt and frees the unique index.
    @household.payment_processor.subscriptions.create!(
      name: "default", processor_id: "sub_webhook", processor_plan: "price_inline", status: "active",
      current_period_start: Time.current, current_period_end: 1.month.from_now, metadata: { "billing_consent_id" => held.id }
    )
    assert held.reload.confirmed?
    assert_nil BillingConsent.held_checkout(@household.id)

    assert_no_difference -> { BillingConsent.count } do
      assert_nil BillingConsent.reserve(BillingOffer.for(:annual), household: @household, user: @user)
    end
  end

  test "an open session past its hold is asked about, and stays held while Stripe still reports it open" do
    held = open_attempt(accepted_at: (BillingConsent::CHECKOUT_HOLD + 1.minute).ago)

    with_checkout_session_retrieve(checkout_session(held, status: "open")) do |requested|
      BillingConsent.recover!
      assert_equal [ "cs_open" ], requested
    end

    assert_equal "open", held.reload.checkout_state
    assert_nil BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
  end

  test "an open session past its hold that Stripe reports complete is synced, confirmed and blocks another" do
    held = open_attempt(accepted_at: (BillingConsent::CHECKOUT_HOLD + 1.minute).ago)

    with_checkout_session_retrieve(checkout_session(held, status: "complete", subscription: "sub_lost_webhook")) do
      with_checkout_sync(@household, subscription_id: "sub_lost_webhook", status: "active", consent: held) do |synced|
        assert_enqueued_jobs 1, only: BillingConsentAcknowledgmentJob do
          assert_equal 1, BillingConsent.recover![:reconciled_checkouts]
        end
        assert_equal [ "cs_open" ], synced
      end
    end

    held.reload
    assert_equal [ "confirmed", "sub_lost_webhook" ], [ held.checkout_state, held.subscription_processor_id ]
    assert_nil BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
  end

  test "a complete session whose subscription is not active yet hands the hold to that subscription" do
    held = open_attempt(accepted_at: (BillingConsent::CHECKOUT_HOLD + 1.minute).ago)

    with_checkout_session_retrieve(checkout_session(held, status: "complete", subscription: "sub_incomplete")) do
      with_checkout_sync(@household, subscription_id: "sub_incomplete", status: "incomplete", consent: held) do
        assert held.reconcile_checkout!
      end
    end

    assert_equal "completed", held.reload.checkout_state
    assert_not held.confirmed?
    assert_nil BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user), "the incomplete subscription blocks"

    # Once Stripe ends that subscription unpaid, the household can try again.
    Pay::Subscription.where(processor_id: "sub_incomplete").update_all(status: "incomplete_expired")
    assert BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
  end

  test "a complete session whose subscription Pay did not record stays held" do
    held = open_attempt(accepted_at: (BillingConsent::CHECKOUT_HOLD + 1.minute).ago)
    original = Pay::Stripe.method(:sync_checkout_session)
    Pay::Stripe.define_singleton_method(:sync_checkout_session) { |*, **| nil }

    with_checkout_session_retrieve(checkout_session(held, status: "complete", subscription: "sub_not_synced")) do
      assert_not held.reconcile_checkout!
    end

    assert_equal "open", held.reload.checkout_state
    assert_nil BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
  ensure
    Pay::Stripe.define_singleton_method(:sync_checkout_session, original)
  end

  test "a session Stripe reports expired frees the household" do
    held = open_attempt(accepted_at: (BillingConsent::CHECKOUT_HOLD + 1.minute).ago)

    with_checkout_session_retrieve(checkout_session(held, status: "expired")) do
      BillingConsent.recover!
    end

    assert_equal "expired", held.reload.checkout_state
    assert BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
  end

  test "a session that does not name this consent and customer settles nothing" do
    held = open_attempt(accepted_at: (BillingConsent::CHECKOUT_HOLD + 1.minute).ago)

    [ checkout_session(held, status: "expired").merge(customer: "cus_someone_else"),
      checkout_session(held, status: "expired").merge(metadata: {}) ].each do |session|
      with_checkout_session_retrieve(session) { assert_not held.reconcile_checkout! }
    end

    assert_equal "open", held.reload.checkout_state
  end

  test "every held attempt past its hold stays held while Stripe cannot be reached" do
    down = Stripe::APIConnectionError.new("down")
    original_list = Stripe::Checkout::Session.method(:list)
    Stripe::Checkout::Session.define_singleton_method(:list) { |*| raise down }

    %w[reserved unknown open].each do |state|
      BillingConsent.held_checkouts.delete_all
      held = open_attempt(accepted_at: (BillingConsent::CHECKOUT_HOLD + 1.minute).ago)
      held.update_columns(checkout_state: state, checkout_session_id: nil) unless state == "open"

      with_checkout_session_retrieve(down) do
        assert_equal 0, BillingConsent.recover![:reconciled_checkouts], state
      end

      assert_equal state, held.reload.checkout_state, state
      assert_nil BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user), state
    end
  ensure
    Stripe::Checkout::Session.define_singleton_method(:list, original_list)
  end

  test "reconciling an unknown attempt finds the session its metadata names and creates none" do
    held = unknown_attempt
    session = { id: "cs_found", object: "checkout.session", status: "open", customer: "cus_consent",
                metadata: { billing_consent_id: held.id } }
    stranger = { id: "cs_other", object: "checkout.session", status: "open", customer: "cus_consent", metadata: {} }

    with_checkout_sessions([ stranger, session ]) do |requested|
      assert held.reconcile_checkout!
      assert_equal "cus_consent", requested.sole[:customer]
    end

    held.reload
    assert_equal [ "open", "cs_found" ], [ held.checkout_state, held.checkout_session_id ]
    assert_nil BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user), "the open session still holds"
  end

  test "an unknown attempt Stripe has no session for is released only once its request has settled" do
    held = unknown_attempt

    with_checkout_sessions([]) do
      assert_not held.reconcile_checkout!, "too early: Stripe may still be finishing the request"
      assert_equal "unknown", held.reload.checkout_state

      travel BillingConsent::CHECKOUT_SETTLE_TIME + 1.minute do
        assert held.reconcile_checkout!
      end
    end

    assert_equal "expired", held.reload.checkout_state
    assert BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
  end

  test "an unknown attempt stays held while Stripe cannot be asked" do
    held = unknown_attempt
    original = Stripe::Checkout::Session.method(:list)
    Stripe::Checkout::Session.define_singleton_method(:list) { |*| raise Stripe::APIConnectionError, "down" }

    travel BillingConsent::CHECKOUT_SETTLE_TIME + 1.minute do
      assert_not held.reconcile_checkout!
    end
    assert_equal "unknown", held.reload.checkout_state
  ensure
    Stripe::Checkout::Session.define_singleton_method(:list, original)
  end

  # --- Acknowledgment ----------------------------------------------------------

  test "a send that fails before reaching the mail server is retried on schedule and sent once" do
    attempts = fail_first_sends(1)

    assert_no_emails { assert_not BillingConsentAcknowledgmentJob.perform_now(@consent.id) }
    @consent.reload
    assert_nil @consent.acknowledgment_claimed_at
    assert_equal 1, @consent.acknowledgment_attempts
    assert_match "SMTP unavailable", @consent.acknowledgment_last_error
    assert @consent.acknowledgment_next_attempt_at.future?
    assert_no_emails { BillingConsent.recover! }

    travel 2.minutes do
      assert_emails(1) { BillingConsent.recover! }
      assert_no_emails { BillingConsent.recover! }
    end

    assert_equal 2, attempts.call
    assert @consent.reload.acknowledged?
  end

  test "a refused connection is definitely unsent, so it is retried" do
    sends = 0
    behavior = lambda do |mail|
      sends += 1
      raise Errno::ECONNREFUSED, "smtp" if sends == 1

      ActionMailer::Base.deliveries << mail
    end

    with_delivery(behavior) do
      assert_no_emails { assert_not @consent.deliver_acknowledgment }
      assert_nil @consent.reload.acknowledgment_claimed_at
      assert_nil @consent.acknowledgment_uncertain_at

      travel 2.minutes do
        assert_emails(1) { BillingConsent.recover! }
      end
    end
    assert @consent.reload.acknowledged?
  end

  test "a message the server accepted before the connection failed is never sent again automatically" do
    accepted = lambda do |mail|
      ActionMailer::Base.deliveries << mail
      raise EOFError, "connection closed after 250 OK"
    end

    with_delivery(accepted) do
      assert_emails(1) do
        assert_error_reported(EOFError) { assert_not @consent.deliver_acknowledgment }
      end
    end

    @consent.reload
    assert @consent.acknowledgment_uncertain?
    assert_match "EOFError", @consent.acknowledgment_last_error
    assert_not @consent.acknowledged?

    travel 1.day do
      assert_no_emails do
        BillingConsent.recover!
        assert_not @consent.deliver_acknowledgment
        assert_equal 0, BillingConsent.retry_unsent_acknowledgments
        perform_enqueued_jobs { BillingConsentAcknowledgmentJob.perform_later(@consent.id) }
      end
      assert_equal 1, BillingConsent.recover![:awaiting_operator]
    end
  end

  test "an operator settles an uncertain send from the mail provider's log" do
    delivered = BillingConsent.record!(BillingOffer.for(:monthly), household: households(:two), user: @user)
    delivered.update_columns(confirmed_at: Time.current, checkout_state: "confirmed", **verified_payment)
    [ @consent, delivered ].each { |consent| consent.mark_acknowledgment_uncertain!("lost") }

    delivered.resolve_uncertain_acknowledgment!(delivered: true)
    assert delivered.reload.acknowledged?

    assert_enqueued_jobs 1, only: BillingConsentAcknowledgmentJob do
      @consent.resolve_uncertain_acknowledgment!(delivered: false)
    end
    assert_emails(1) { perform_enqueued_jobs(only: BillingConsentAcknowledgmentJob) }
    assert @consent.reload.acknowledged?
  end

  test "a send whose worker vanished is held for an operator, not resent" do
    @consent.update_columns(acknowledgment_claimed_at: 1.minute.ago)
    assert_no_emails { assert_not @consent.deliver_acknowledgment }
    BillingConsent.recover!
    assert_not @consent.reload.acknowledgment_uncertain?, "another worker may still be sending"

    travel BillingConsent::ACKNOWLEDGMENT_CLAIM_TIMEOUT + 1.minute do
      assert_no_emails { BillingConsent.recover! }
    end

    @consent.reload
    assert @consent.acknowledgment_uncertain?
    assert_match "worker was lost", @consent.acknowledgment_last_error
    assert_no_emails { assert_not @consent.deliver_acknowledgment }
  end

  test "a failed enqueue at confirmation leaves the acknowledgment due, and recovery sends it once" do
    @consent.update_columns(acknowledgment_sent_at: Time.current)
    consent =BillingConsent.record!(BillingOffer.for(:monthly), household: @household, user: @user)
    consent.record_checkout_session!("cs_test_enqueue")
    BillingConsentAcknowledgmentJob.define_singleton_method(:perform_later) { |*| raise ActiveJob::EnqueueError, "queue down" }

    assert_error_reported(ActiveJob::EnqueueError) do
      simulated_subscription(consent)
    end

    consent.reload
    assert consent.confirmed?
    assert_not consent.acknowledged?
    assert consent.acknowledgment_next_attempt_at <= Time.current
    BillingConsentAcknowledgmentJob.singleton_class.remove_method(:perform_later)

    summary = nil
    assert_emails(1) { summary = BillingConsent.recover! }
    assert_operator summary[:sent_acknowledgments], :>=, 1
    assert consent.reload.acknowledged?
    assert_equal "$5 USD", consent.paid_label, "the simulated provider charged the plan price"
    assert_no_emails { BillingConsent.recover! }
  end

  test "a queue that silently refuses the job is treated like a failed enqueue" do
    BillingConsentAcknowledgmentJob.define_singleton_method(:perform_later) { |*| false }

    assert_error_reported(ActiveJob::EnqueueError) { assert_not @consent.enqueue_acknowledgment }
  end

  test "the recurring schedule runs recovery in production" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml")).fetch("production")
    task = schedule.fetch("billing_consent_recovery")

    assert_equal "every 5 minutes", task["schedule"]
    # Solid Queue evaluates the command the same way.
    assert_emails(1) { eval(task["command"]) }
  end

  test "the payment is read from Stripe, with its discount, period and next renewal" do
    consent = stripe_confirmed_consent
    period_start = Time.utc(2026, 10, 3, 12)
    period_end = Time.utc(2027, 10, 3, 12)

    with_stripe_payment("sub_paid", amount_paid: 2500, discount: 2500, period_start: period_start, period_end: period_end,
                        subscription: stripe_subscription("sub_paid", period_end: period_end)) do |requested|
      assert_emails(1) { assert consent.deliver_acknowledgment }
      assert_equal "sub_paid", requested.sole[:subscription]
    end

    consent.reload
    assert_equal [ 2500, 2500, "usd", "in_sub_paid" ],
      [ consent.paid_amount_minor_units, consent.paid_discount_minor_units, consent.paid_currency, consent.provider_invoice_id ]
    assert_equal [ period_start, period_end, period_end ], [ consent.paid_period_start, consent.paid_period_end, consent.next_renewal_at ]

    mail = ActionMailer::Base.deliveries.last
    paid_on, renews_on = long_date(period_start), long_date(period_end)
    assert_match(/\AOctober 0?3, 2026\z/, paid_on)
    assert_match(/\AOctober 0?3, 2027\z/, renews_on)
    [ mail.text_part.body.decoded, mail.html_part.body.decoded ].each do |body|
      assert_includes body, "Amount paid:"
      assert_includes body, "$25 USD on #{paid_on}, after a discount of $25 USD"
      assert_includes body, "#{paid_on} to #{renews_on}"
      assert_includes body, "#{renews_on}, unless you cancel before then"
      assert_includes body, "$50 USD per year"
    end
  end

  test "a subscription set to cancel has no next renewal" do
    consent = stripe_confirmed_consent

    with_stripe_payment("sub_paid", amount_paid: 5000,
                        subscription: stripe_subscription("sub_paid", cancel_at_period_end: true)) do
      assert_emails(1) { assert consent.deliver_acknowledgment }
    end

    assert_nil consent.reload.next_renewal_at
    assert_includes ActionMailer::Base.deliveries.last.text_part.body.decoded, "Next renewal: none"
  end

  test "nothing is sent until Stripe reports the payment, and then it is" do
    @consent.update_columns(acknowledgment_sent_at: Time.current)
    consent = stripe_confirmed_consent

    with_stripe_payment("sub_paid", amount_paid: 5000, status: "open", subscription: stripe_subscription("sub_paid")) do
      assert_no_emails { assert_not consent.deliver_acknowledgment }
    end
    consent.reload
    assert_nil consent.paid_amount_minor_units
    assert_match "no paid invoice", consent.acknowledgment_last_error

    travel 2.minutes do
      with_stripe_payment("sub_paid", amount_paid: 5000, subscription: stripe_subscription("sub_paid")) do
        assert_emails(1) { BillingConsent.recover! }
      end
    end
  end

  test "an acknowledgment out of attempts waits for an operator, who can queue it again" do
    @consent.update_columns(acknowledgment_attempts: BillingConsent::ACKNOWLEDGMENT_MAX_ATTEMPTS - 1)
    fail_first_sends(1)

    assert_error_reported(RuntimeError) { assert_not @consent.deliver_acknowledgment }
    @consent.reload
    assert @consent.acknowledgment_failed_at
    assert_nil @consent.acknowledgment_next_attempt_at
    travel(1.day) { assert_no_emails { BillingConsent.recover! } }

    assert_equal 1, BillingConsent.retry_unsent_acknowledgments
    assert_emails(1) { perform_enqueued_jobs(only: BillingConsentAcknowledgmentJob) }
    assert_equal 0, BillingConsent.retry_unsent_acknowledgments
  end

  test "an unconfirmed consent, such as an abandoned Checkout, is never acknowledged" do
    @consent.update_columns(confirmed_at: nil)

    assert_no_emails { assert_not @consent.deliver_acknowledgment }
    assert_no_emails { BillingConsent.recover! }
    assert_no_enqueued_jobs { BillingConsent.retry_unsent_acknowledgments }
  end

  test "the acknowledgment repeats the agreed terms, the refund rule and how to cancel" do
    mail = BillingConsentMailer.acknowledgment(@consent)

    assert_equal [ @user.email ], mail.to
    [ mail.text_part.body.decoded, mail.html_part.body.decoded ].each do |body|
      assert_includes body, "$50 USD per year"
      assert_includes body, BillingOffer::IMMEDIATE_CHARGE
      assert_includes body, "renews automatically every year until you cancel"
      assert_includes body, "To request a refund, contact"
      assert_includes body, "support@familyplates.org within 7 days of the charge. We may grant a refund."
      assert_includes body, "Refunds are considered case by case and are not guaranteed, except where a law that applies to that charge requires one."
      assert_includes body, "not refunded"
      assert_includes body, "Amount paid:"
      assert_includes body, "Paid period:"
      assert_includes body, "Next renewal:"
      assert_includes body, "Cancel Subscription"
      assert_not_includes body, "after a discount", "no discount was applied"
    end
    assert_includes mail.html_part.body.decoded, 'href="mailto:support@familyplates.org"'
    # Both parts carry the disclosure's refund sentence word for word.
    assert_match(/Refunds:\r?\n#{Regexp.escape(BillingOffer::REFUND_REQUEST)}/, mail.text_part.body.decoded)
    assert_includes mail.html_part.body.decoded.gsub(/<[^>]+>/, ""), BillingOffer::REFUND_REQUEST
    assert_includes @consent.disclosure, BillingOffer::REFUND_REQUEST
  end

  test "the record survives deleting the user it names" do
    @household.update_columns(billing_owner_user_id: nil)

    assert_nothing_raised { @user.destroy! }
    assert BillingConsent.exists?(@consent.id)
  end

  private

  # The acknowledgment's date format, so these tests check which day is shown
  # rather than how Rails pads it.
  def long_date(time)
    time.utc.to_date.to_formatted_s(:long)
  end

  def unknown_attempt
    @household.set_payment_processor :stripe, allow_fake: true, processor_id: "cus_consent"
    held = BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
    held.update_columns(checkout_state: "unknown")
    held
  end

  def open_attempt(accepted_at: Time.current)
    @household.set_payment_processor :stripe, allow_fake: true, processor_id: "cus_consent"
    held = BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
    held.update_columns(checkout_state: "open", checkout_session_id: "cs_open", accepted_at: accepted_at)
    held
  end

  def checkout_session(consent, status:, subscription: nil)
    { id: "cs_open", object: "checkout.session", status: status, customer: "cus_consent", subscription: subscription,
      metadata: { billing_consent_id: consent.id } }
  end

  def stripe_confirmed_consent
    @household.set_payment_processor :stripe, allow_fake: true, processor_id: "cus_consent"
    subscription = @household.payment_processor.subscriptions.create!(
      name: "default", processor_id: "sub_paid", processor_plan: "price_inline", status: "incomplete",
      current_period_start: Time.current, current_period_end: 1.year.from_now
    )
    consent = BillingConsent.record!(BillingOffer.for(:annual), household: households(:two), user: @user)
    consent.update_columns(confirmed_at: Time.current, checkout_state: "confirmed",
      pay_subscription_id: subscription.id, subscription_processor_id: "sub_paid")
    consent
  end

  def simulated_subscription(consent)
    @household.set_payment_processor :fake_processor, allow_fake: true
    @household.payment_processor.subscriptions.create!(
      name: "default", processor_id: "sub_sim_enqueue", processor_plan: consent.stripe_price_id || "monthly", status: "active",
      current_period_start: Time.current, current_period_end: 1.month.from_now,
      metadata: { "billing_consent_id" => consent.id }
    )
  end

  # Makes the first `failures` sends raise before any delivery, then sends
  # for real. Returns a lambda reporting how many sends were attempted.
  def fail_first_sends(failures)
    count = 0
    BillingConsentMailer.singleton_class.define_method(:acknowledgment) do |consent|
      count += 1
      raise "SMTP unavailable" if count <= failures

      ActionMailer::MessageDelivery.new(BillingConsentMailer, :acknowledgment, consent)
    end
    -> { count }
  end
end
