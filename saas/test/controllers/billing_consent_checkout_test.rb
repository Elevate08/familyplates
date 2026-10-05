# frozen_string_literal: true

require "test_helper"

# Paid checkout needs the billing owner's agreement to the renewal terms shown
# beside the button, checked on the server, recorded before Stripe is asked
# for anything, and acknowledged by email only once the subscription is live.
# Stripe is stubbed throughout; nothing here calls it.
class BillingConsentCheckoutTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include BillingConsentTestHelper

  setup do
    FamilyPlates.config.reset!
    FamilyPlates.config.mode = "hosted"
    @admin = family_members(:one)
    @household = @admin.household
    @user = User.create!(email: "owner@household.test", **accepted_terms)
    @admin.update!(user: @user)
    @household.update!(billing_owner: @user)
    @saved_env = %w[STRIPE_SECRET_KEY ENABLE_REAL_STRIPE_TESTS STRIPE_MONTHLY_PRICE_ID STRIPE_ANNUAL_PRICE_ID]
      .to_h { |name| [ name, ENV[name] ] }
    %w[ENABLE_REAL_STRIPE_TESTS STRIPE_MONTHLY_PRICE_ID STRIPE_ANNUAL_PRICE_ID].each { |name| ENV.delete(name) }

    sign_in_user(@user)
    sign_in_as(@admin)
  end

  teardown do
    @saved_env.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
    FamilyPlates.config.reset!
  end

  test "each plan shows its price and renewal terms beside an unticked box" do
    get subscription_path

    assert_response :success
    assert_select "input[type=checkbox][name=accept_renewal_terms]", count: 2
    assert_select "input[type=checkbox][name=accept_renewal_terms][checked]", count: 0
    assert_select "input[type=hidden][name=offer_token]", count: 2
    assert_select "[data-testid=billing-disclosure-monthly]", text: /\$5 USD per month\. It renews automatically every month until you cancel\./
    assert_select "[data-testid=billing-disclosure-annual]", text: /\$50 USD per year\. It renews automatically every year until you cancel\./
    %w[monthly annual].each do |plan|
      assert_select "[data-testid=billing-disclosure-#{plan}]", text: /#{Regexp.escape(BillingOffer::IMMEDIATE_CHARGE)}/
      assert_select "[data-testid=billing-disclosure-#{plan}]", text: /Cancel anytime on the Subscription & Billing page/
      assert_select "[data-testid=billing-disclosure-#{plan}]", text: /not refunded for the rest of a billing period/
    end
    assert_no_match "Priority feature requests", response.body
    assert_no_match "community access", response.body
    assert_no_match "One annual payment", response.body
  end

  test "Checkout is never started without the ticked box and a current offer for this owner" do
    stranger = User.create!(email: "stranger@household.test")
    fresh = -> { BillingOffer.for(:monthly).token_for(household: @household, user: @user) }
    attempts = {
      "no box" => { plan: "monthly", offer_token: fresh.call },
      "box unticked" => { plan: "monthly", accept_renewal_terms: "0", offer_token: fresh.call },
      "no offer token" => { plan: "monthly", accept_renewal_terms: "1" },
      "forged token" => { plan: "monthly", accept_renewal_terms: "1", offer_token: "forged" },
      "token for the other plan" => { plan: "monthly", accept_renewal_terms: "1",
                                      offer_token: BillingOffer.for(:annual).token_for(household: @household, user: @user) },
      "token for another user" => { plan: "monthly", accept_renewal_terms: "1",
                                    offer_token: BillingOffer.for(:monthly).token_for(household: @household, user: stranger) },
      "token for another household" => { plan: "monthly", accept_renewal_terms: "1",
                                         offer_token: BillingOffer.for(:monthly).token_for(household: households(:two), user: @user) }
    }

    attempts.each do |label, params|
      assert_no_checkout(label) { post subscription_path, params: params }
    end
  end

  test "an offer accepted after it expired is refused" do
    params = consent_params(:monthly, household: @household, user: @user)

    travel BillingOffer::TOKEN_TTL + 1.minute do
      assert_no_checkout("expired") { post subscription_path, params: params }
    end
  end

  test "an offer accepted after its terms or price changed is refused" do
    params = consent_params(:monthly, household: @household, user: @user)
    ENV["STRIPE_MONTHLY_PRICE_ID"] = "price_changed_since_render"

    assert_no_checkout("stale") { post subscription_path, params: params }
    assert_match "terms have changed", flash[:alert]
  end

  test "the simulated checkout also refuses a missing consent" do
    assert_no_difference -> { Pay::Subscription.count } do
      post subscription_path, params: { plan: "annual" }
    end

    assert_redirected_to subscription_path
    assert_match "tick the box", flash[:alert]
    assert_not @household.reload.active_subscription?
  end

  test "a configured Stripe price that differs from the page stops Checkout" do
    ENV["STRIPE_MONTHLY_PRICE_ID"] = "price_test_monthly"
    wrong = {
      "amount" => stripe_price(unit_amount: 600),
      "currency" => stripe_price(currency: "eur"),
      "interval" => stripe_price(recurring: { interval: "year", interval_count: 1 }),
      "interval count" => stripe_price(recurring: { interval: "month", interval_count: 3 }),
      "archived" => stripe_price(active: false),
      "one-time" => stripe_price(recurring: nil),
      "unreadable" => Stripe::InvalidRequestError.new("No such price", "price")
    }

    wrong.each do |label, price|
      with_price_retrieve(price) do
        assert_no_checkout(label) do
          post subscription_path, params: consent_params(:monthly, household: @household, user: @user)
        end
      end
      assert_equal SubscriptionsController::CHECKOUT_UNAVAILABLE, flash[:alert], label
    end
  end

  test "a configured Stripe price that matches the page goes to Checkout" do
    ENV["STRIPE_MONTHLY_PRICE_ID"] = "price_test_monthly"

    created = with_price_retrieve(stripe_price) { checkout(:monthly) }

    assert_equal "price_test_monthly", created[:line_items].first[:price]
    assert_equal "price_test_monthly", BillingConsent.sole.stripe_price_id
  end

  test "an accepted offer is recorded and named in the Checkout session and subscription" do
    created = checkout(:annual)

    consent = BillingConsent.sole
    offer = BillingOffer.for(:annual)
    assert_equal @user.id, consent.user_id
    assert_equal @household.id, consent.household_id
    assert_equal Legal::TERMS_VERSION, consent.terms_version
    assert_equal offer.disclosure, consent.disclosure
    assert_includes consent.disclosure, BillingOffer::IMMEDIATE_CHARGE
    assert_equal offer.digest, consent.disclosure_digest
    assert_equal "annual", consent.plan_key
    assert_nil consent.stripe_price_id, "no Price is configured, so Checkout gets the amount inline"
    assert_equal [ "usd", 5000, "year" ], [ consent.currency, consent.amount_minor_units, consent.interval ]
    assert_in_delta Time.current, consent.accepted_at, 5.seconds
    assert_equal "cs_test_stub", consent.checkout_session_id
    assert_equal "open", consent.checkout_state
    assert_not consent.confirmed?

    # One consent is one attempt: Stripe replays rather than repeats a request with this key.
    assert_equal({ idempotency_key: consent.checkout_idempotency_key }, @checkout_options)
    assert_equal "cus_checkout", created[:customer]
    assert_equal "subscription", created[:mode]
    assert_equal consent.accepted_at.to_i + BillingConsent::CHECKOUT_LIFETIME.to_i, created[:expires_at]
    assert_equal "http://www.example.com/subscription?success=true&stripe_checkout_session_id={CHECKOUT_SESSION_ID}", created[:success_url]
    assert_equal "http://www.example.com/subscription?canceled=true&stripe_checkout_session_id={CHECKOUT_SESSION_ID}", created[:cancel_url]
    assert_equal consent.id, created.dig(:metadata, :billing_consent_id)
    assert_equal consent.id, created.dig(:subscription_data, :metadata, :billing_consent_id)
    item = created[:line_items].first[:price_data]
    assert_equal [ "usd", 5000, { interval: "year" } ], [ item[:currency], item[:unit_amount], item[:recurring] ]
    # Paying ends the free trial: Checkout does not add a Stripe trial on top.
    assert_nil created.dig(:subscription_data, :trial_period_days)
    assert_nil created.dig(:subscription_data, :trial_end)
    assert_enqueued_jobs 0, only: BillingConsentAcknowledgmentJob
  end

  test "returning from a completed Checkout confirms the consent and sends one acknowledgment" do
    checkout(:monthly)
    consent = BillingConsent.sole

    with_checkout_return(subscription_status: "active", consent: consent) do
      assert_enqueued_jobs 1, only: BillingConsentAcknowledgmentJob do
        get subscription_path(success: true, stripe_checkout_session_id: "cs_test_stub")
      end
      assert_match "Thank you for subscribing", flash[:notice]

      # Reloading the return page, or the webhook syncing the same subscription, queues nothing more.
      assert_no_enqueued_jobs only: BillingConsentAcknowledgmentJob do
        get subscription_path(success: true, stripe_checkout_session_id: "cs_test_stub")
      end
    end

    consent.reload
    assert consent.confirmed?
    assert_equal "sub_checkout", consent.subscription_processor_id
    assert_equal @household.payment_processor.subscription.id, consent.pay_subscription_id

    with_stripe_payment("sub_checkout", amount_paid: 500, subscription: stripe_subscription("sub_checkout")) do
      assert_emails 1 do
        perform_enqueued_jobs(only: BillingConsentAcknowledgmentJob)
      end
    end
    mail = ActionMailer::Base.deliveries.last
    assert_equal [ @user.email ], mail.to
    body = mail.text_part.body.decoded
    assert_includes body, "$5 USD per month"
    paid_on = Date.new(2026, 10, 3).to_formatted_s(:long)
    renews_on = Date.new(2026, 11, 3).to_formatted_s(:long)
    assert_match(/\ANovember 0?3, 2026\z/, renews_on)
    assert_includes body, "Amount paid: $5 USD on #{paid_on}"
    assert_includes body, "Paid period: #{paid_on} to #{renews_on}"
    assert_includes body, "Next renewal: #{renews_on}"
    assert_includes body, BillingOffer::REFUND_REQUEST
    assert_includes body, BillingOffer::IMMEDIATE_CHARGE
    assert_includes body, "choose Cancel Subscription"
    assert_includes body, "http://example.com/subscription"
    assert_includes body, consent.terms_version
    assert consent.reload.acknowledged?
  end

  test "a return from Checkout settles an attempt whose create answer was lost" do
    @household.set_payment_processor :stripe, allow_fake: true, processor_id: "cus_checkout"
    consent = BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
    consent.update_columns(checkout_state: "unknown")

    with_checkout_return(subscription_status: "active", consent: consent, session_metadata: { billing_consent_id: consent.id }) do
      assert_enqueued_jobs 1, only: BillingConsentAcknowledgmentJob do
        get subscription_path(success: true, stripe_checkout_session_id: "cs_test_stub")
      end
    end

    consent.reload
    assert_equal [ "confirmed", "cs_test_stub" ], [ consent.checkout_state, consent.checkout_session_id ]
    assert_equal 1, BillingConsent.count
  end

  test "an abandoned Checkout confirms nothing, sends nothing and says nothing was charged" do
    checkout(:monthly)
    consent = BillingConsent.sole

    with_checkout_return(subscription_status: nil, consent: consent) do
      get subscription_path(canceled: true, stripe_checkout_session_id: "cs_test_stub")
    end

    assert_response :success
    assert_equal "Checkout was not completed. You have not been charged and no subscription was started.", flash[:notice]
    assert_not consent.reload.confirmed?
    assert_not @household.reload.active_subscription?
    assert_no_enqueued_jobs only: BillingConsentAcknowledgmentJob
    assert_no_emails { perform_enqueued_jobs }
  end

  test "a Checkout that Stripe refuses to start leaves no consent behind and frees the household" do
    refusals = {
      "invalid request" => Stripe::InvalidRequestError.new("No such customer", "customer", http_status: 400),
      "bad key" => Stripe::AuthenticationError.new("Invalid API key", http_status: 401)
    }

    refusals.each do |label, error|
      with_session_create(-> { raise error }) do |calls|
        assert_no_difference -> { BillingConsent.count }, label do
          post subscription_path, params: consent_params(:monthly, household: @household, user: @user)
        end
        assert_equal 1, calls.size, label
      end

      assert_redirected_to subscription_path
      assert_equal SubscriptionsController::CHECKOUT_UNAVAILABLE, flash[:alert], label
      assert_nil BillingConsent.held_checkout(@household.id), label
    end
  end

  test "a Checkout create whose outcome is unknown keeps its consent and blocks a second create" do
    lost = {
      "no answer" => Stripe::APIConnectionError.new("read timeout"),
      "server error" => Stripe::APIError.new("internal", http_status: 500),
      "same key still running" => Stripe::InvalidRequestError.new("conflict", nil, http_status: 409),
      "key reused" => Stripe::IdempotencyError.new("keys for idempotent requests", http_status: 400)
    }

    lost.each do |label, error|
      BillingConsent.delete_all
      first_options = nil
      with_session_create(->(options) { first_options = options; raise error }) do
        assert_error_reported(error.class) do
          post subscription_path, params: consent_params(:monthly, household: @household, user: @user)
        end
      end

      assert_redirected_to subscription_path
      assert_equal SubscriptionsController::CHECKOUT_OUTCOME_UNKNOWN, flash[:alert], label
      consent = BillingConsent.sole
      assert_equal "unknown", consent.checkout_state, label
      assert_match error.class.name, consent.checkout_error, label
      assert_equal({ idempotency_key: consent.checkout_idempotency_key }, first_options, label)

      # Retrying asks Stripe what happened and never asks for a second session.
      with_checkout_sessions([]) do |lookups|
        with_session_create(-> { flunk "#{label}: a second Checkout session was requested" }) do
          assert_no_difference -> { BillingConsent.count }, label do
            post subscription_path, params: consent_params(:monthly, household: @household, user: @user)
          end
        end
        assert_equal [ "cus_checkout" ], lookups.map { |params| params[:customer] }, label
      end
      assert_equal SubscriptionsController::CHECKOUT_OUTCOME_UNKNOWN, flash[:alert], label
      assert_equal "unknown", consent.reload.checkout_state, label
    end
  end

  test "an unknown Checkout Stripe never created frees the household once the request has settled" do
    with_session_create(-> { raise Stripe::APIConnectionError, "read timeout" }) do
      post subscription_path, params: consent_params(:monthly, household: @household, user: @user)
    end
    lost = BillingConsent.sole

    travel BillingConsent::CHECKOUT_SETTLE_TIME + 1.minute do
      sign_in_user(@user)
      sign_in_as(@admin)
      created = nil
      with_checkout_sessions([]) do
        with_session_create(->(options) { created = options; Stripe::Checkout::Session.construct_from(id: "cs_retry", url: "https://checkout.stripe.com/c/pay/cs_retry") }) do
          post subscription_path, params: consent_params(:monthly, household: @household, user: @user)
        end
      end

      assert_redirected_to "https://checkout.stripe.com/c/pay/cs_retry"
      retry_consent = BillingConsent.where.not(id: lost.id).sole
      assert_equal({ idempotency_key: retry_consent.checkout_idempotency_key }, created)
      assert_not_equal lost.checkout_idempotency_key, retry_consent.checkout_idempotency_key
    end

    assert_equal "expired", lost.reload.checkout_state
  end

  test "an unknown Checkout Stripe did create is recorded, not repeated" do
    with_session_create(-> { raise Stripe::APIConnectionError, "read timeout" }) do
      post subscription_path, params: consent_params(:monthly, household: @household, user: @user)
    end
    lost = BillingConsent.sole
    found = { id: "cs_was_created", object: "checkout.session", status: "open", customer: "cus_checkout",
              metadata: { billing_consent_id: lost.id } }

    with_checkout_sessions([ found ]) do
      with_session_create(-> { flunk "a second Checkout session was requested" }) do
        post subscription_path, params: consent_params(:monthly, household: @household, user: @user)
      end
    end

    assert_equal SubscriptionsController::CHECKOUT_IN_PROGRESS, flash[:alert]
    assert_equal [ "open", "cs_was_created" ], [ lost.reload.checkout_state, lost.checkout_session_id ]
    assert_equal 1, BillingConsent.count
  end

  test "a Checkout Stripe completed after the create answer was lost is synced on retry, never repeated" do
    with_session_create(-> { raise Stripe::APIConnectionError, "read timeout" }) do
      post subscription_path, params: consent_params(:monthly, household: @household, user: @user)
    end
    lost = BillingConsent.sole
    completed = { id: "cs_paid_after_timeout", object: "checkout.session", status: "complete", customer: "cus_checkout",
                  subscription: "sub_paid_after_timeout", metadata: { billing_consent_id: lost.id } }

    with_checkout_sessions([ completed ]) do
      with_checkout_sync(@household, subscription_id: "sub_paid_after_timeout", status: "active", consent: lost) do |synced|
        with_session_create(-> { flunk "a second Checkout session was requested" }) do |calls|
          assert_enqueued_jobs 1, only: BillingConsentAcknowledgmentJob do
            2.times { post subscription_path, params: consent_params(:monthly, household: @household, user: @user) }
          end
          assert_empty calls
        end
        assert_equal [ "cs_paid_after_timeout" ], synced
      end
    end

    assert_redirected_to subscription_path
    assert_equal SubscriptionsController::CHECKOUT_IN_PROGRESS, flash[:alert]
    assert_equal 1, BillingConsent.count
    assert_equal [ "sub_paid_after_timeout" ], @household.pay_subscriptions.pluck(:processor_id)
    lost.reload
    assert_equal [ "confirmed", "cs_paid_after_timeout", "sub_paid_after_timeout" ],
      [ lost.checkout_state, lost.checkout_session_id, lost.subscription_processor_id ]

    with_stripe_payment("sub_paid_after_timeout", amount_paid: 500, subscription: stripe_subscription("sub_paid_after_timeout")) do
      assert_emails(1) { perform_enqueued_jobs(only: BillingConsentAcknowledgmentJob) }
    end
    assert_no_emails { BillingConsent.recover! }
  end

  test "a completed Checkout whose return and webhook were lost still blocks another one past the hold" do
    checkout(:monthly)
    consent = BillingConsent.sole
    completed = { id: "cs_test_stub", object: "checkout.session", status: "complete", customer: "cus_checkout",
                  subscription: "sub_lost_webhook", metadata: { billing_consent_id: consent.id } }

    travel BillingConsent::CHECKOUT_HOLD + 1.hour do
      sign_in_user(@user)
      sign_in_as(@admin)
      with_checkout_session_retrieve(completed) do |asked|
        with_checkout_sync(@household, subscription_id: "sub_lost_webhook", status: "incomplete", consent: consent) do |synced|
          with_session_create(-> { flunk "a second Checkout session was requested" }) do |calls|
            assert_no_difference -> { BillingConsent.count } do
              post subscription_path, params: consent_params(:monthly, household: @household, user: @user)
            end
            assert_empty calls
          end
          assert_equal [ "cs_test_stub" ], synced
        end
        assert_equal [ "cs_test_stub" ], asked
      end

      assert_redirected_to subscription_path
      assert_equal SubscriptionsController::CHECKOUT_IN_PROGRESS, flash[:alert]
    end

    assert_equal "completed", consent.reload.checkout_state
    assert_not consent.confirmed?
    assert_equal [ "incomplete" ], @household.pay_subscriptions.pluck(:status)
  end

  test "an open Checkout past its hold stays held while Stripe cannot be reached" do
    checkout(:monthly)
    consent = BillingConsent.sole

    travel BillingConsent::CHECKOUT_HOLD + 1.hour do
      sign_in_user(@user)
      sign_in_as(@admin)
      with_checkout_session_retrieve(Stripe::APIConnectionError.new("down")) do
        with_session_create(-> { flunk "a second Checkout session was requested" }) do |calls|
          assert_no_difference -> { BillingConsent.count } do
            post subscription_path, params: consent_params(:monthly, household: @household, user: @user)
          end
          assert_empty calls
        end
        BillingConsent.recover!
      end

      assert_redirected_to subscription_path
      assert_equal SubscriptionsController::CHECKOUT_IN_PROGRESS, flash[:alert]
    end

    assert_equal "open", consent.reload.checkout_state
  end

  test "a Checkout Stripe reports expired lets the household subscribe again" do
    checkout(:monthly)
    consent = BillingConsent.sole
    expired = { id: "cs_test_stub", object: "checkout.session", status: "expired", customer: "cus_checkout",
                metadata: { billing_consent_id: consent.id } }

    travel BillingConsent::CHECKOUT_HOLD + 1.hour do
      sign_in_user(@user)
      sign_in_as(@admin)
      retry_session = Stripe::Checkout::Session.construct_from(id: "cs_retry", url: "https://checkout.stripe.com/c/pay/cs_retry")
      with_checkout_session_retrieve(expired) do
        with_session_create(-> { retry_session }) do |calls|
          post subscription_path, params: consent_params(:monthly, household: @household, user: @user)
          assert_equal 1, calls.size
        end
      end

      assert_redirected_to "https://checkout.stripe.com/c/pay/cs_retry"
    end

    assert_equal "expired", consent.reload.checkout_state
    retry_consent = BillingConsent.where.not(id: consent.id).sole
    assert_equal [ "open", "cs_retry" ], [ retry_consent.checkout_state, retry_consent.checkout_session_id ]
  end

  test "the household's attempt is reserved before Stripe is called, so a racing request cannot start another" do
    racing = nil
    held_during_call = nil
    session = Stripe::Checkout::Session.construct_from(id: "cs_first", url: "https://checkout.stripe.com/c/pay/cs_first")

    # Runs while the first request is waiting on Stripe: a second request's
    # reservation, for either plan, loses to the first.
    during_create = lambda do
      held_during_call = BillingConsent.held_checkout(@household.id)&.checkout_state
      racing = %i[monthly annual].map do |plan|
        BillingConsent.reserve(BillingOffer.for(plan), household: @household, user: @user)
      end
      session
    end

    with_session_create(during_create) do |calls|
      post subscription_path, params: consent_params(:monthly, household: @household, user: @user)
      assert_equal 1, calls.size
    end

    assert_equal "reserved", held_during_call
    assert_equal [ nil, nil ], racing
    assert_redirected_to "https://checkout.stripe.com/c/pay/cs_first"
    assert_equal [ "open", "cs_first" ], [ BillingConsent.sole.checkout_state, BillingConsent.sole.checkout_session_id ]
  end

  test "a subscription Stripe can still bill blocks a second Checkout, whatever its status" do
    @household.set_payment_processor :stripe, allow_fake: true, processor_id: "cus_checkout"
    subscription = @household.payment_processor.subscriptions.create!(
      name: "default", processor_id: "sub_existing", processor_plan: "price_inline", status: "incomplete",
      current_period_start: 1.month.ago, current_period_end: 1.day.from_now
    )

    %w[incomplete past_due unpaid paused trialing active].each do |status|
      subscription.update_columns(status: status)
      assert_no_checkout(status) { post subscription_path, params: consent_params(:monthly, household: @household, user: @user) }
      assert_equal SubscriptionsController::CHECKOUT_IN_PROGRESS, flash[:alert], status
    end

    # Once Stripe has ended it, the household can subscribe again.
    subscription.update_columns(status: "canceled", ends_at: 1.day.ago)
    checkout(:monthly)
  end

  test "a Stripe price check runs only after the reservation, and a refused price frees it" do
    ENV["STRIPE_MONTHLY_PRICE_ID"] = "price_test_monthly"
    held_during_check = :not_checked
    household = @household
    original = Stripe::Price.method(:retrieve)
    Stripe::Price.define_singleton_method(:retrieve) do |*|
      held_during_check = BillingConsent.held_checkout(household.id)&.checkout_state
      raise Stripe::InvalidRequestError.new("No such price", "price", http_status: 404)
    end

    assert_no_checkout("unreadable") { post subscription_path, params: consent_params(:monthly, household: @household, user: @user) }
    assert_equal "reserved", held_during_check
  ensure
    Stripe::Price.define_singleton_method(:retrieve, original)
  end

  # The owner went to Stripe, came back without paying and chose again. Their
  # open session is expired on Stripe first, so it can no longer be paid, and
  # only then is a new one started: never two payable sessions at once.
  test "a new Checkout replaces the owner's own still-open session, expiring it on Stripe first" do
    checkout(:monthly)
    first = BillingConsent.sole
    calls = []
    still_open = { id: "cs_test_stub", object: "checkout.session", status: "open", customer: "cus_checkout",
                   metadata: { billing_consent_id: first.id } }
    originals = %i[expire create].index_with { |name| Stripe::Checkout::Session.method(name) }
    Stripe::Checkout::Session.define_singleton_method(:expire) do |id, *|
      calls << [ :expire, id ]
      Stripe::Checkout::Session.construct_from(still_open.merge(status: "expired"))
    end
    Stripe::Checkout::Session.define_singleton_method(:create) do |*|
      calls << [ :create ]
      Stripe::Checkout::Session.construct_from(id: "cs_second", url: "https://checkout.stripe.com/c/pay/cs_second")
    end

    with_checkout_session_retrieve(still_open) do
      post subscription_path, params: consent_params(:annual, household: @household, user: @user)
    end

    assert_redirected_to "https://checkout.stripe.com/c/pay/cs_second"
    assert_equal [ [ :expire, "cs_test_stub" ], [ :create ] ], calls
    assert_equal "expired", first.reload.checkout_state
    assert_equal [ "open", "annual" ], BillingConsent.where.not(id: first.id).sole.then { |c| [ c.checkout_state, c.plan_key ] }
  ensure
    originals&.each { |name, method| Stripe::Checkout::Session.define_singleton_method(name, method) }
  end

  test "a session Stripe will not expire (it was just paid) keeps the hold, and no second Checkout starts" do
    params = consent_params(:monthly, household: @household, user: @user)
    checkout(:monthly)
    session_count = 0
    originals = %i[expire create].index_with { |name| Stripe::Checkout::Session.method(name) }
    Stripe::Checkout::Session.define_singleton_method(:expire) do |*|
      raise Stripe::InvalidRequestError.new("Only Checkout Sessions with a status in [\"open\"] can be expired.", nil, http_status: 400)
    end
    Stripe::Checkout::Session.define_singleton_method(:create) { |*| session_count += 1 }
    still_open = { id: "cs_test_stub", object: "checkout.session", status: "open", customer: "cus_checkout",
                   metadata: { billing_consent_id: BillingConsent.sole.id } }

    with_checkout_session_retrieve(still_open) do |asked|
      assert_no_difference -> { BillingConsent.count } do
        post subscription_path, params: params
      end
      assert_equal [ "cs_test_stub" ], asked, "Stripe is asked whether the open session completed"
    end

    assert_redirected_to subscription_path
    assert_equal SubscriptionsController::CHECKOUT_IN_PROGRESS, flash[:alert]
    assert_equal 0, session_count
    assert_equal "open", BillingConsent.sole.checkout_state
  ensure
    originals&.each { |name, method| Stripe::Checkout::Session.define_singleton_method(name, method) }
  end

  test "the simulated checkout records, confirms and acknowledges consent the same way" do
    assert_enqueued_jobs 1, only: BillingConsentAcknowledgmentJob do
      post subscription_path, params: consent_params(:annual, household: @household, user: @user)
    end

    consent = BillingConsent.sole
    assert consent.confirmed?
    assert_equal @household.payment_processor.subscription.processor_id, consent.subscription_processor_id
    assert_emails(1) { perform_enqueued_jobs(only: BillingConsentAcknowledgmentJob) }
  end

  test "the no-card trial ends without a charge, a subscription or a consent" do
    @household.update_columns(created_at: (Household::FREE_TRIAL_DAYS + 1).days.ago)

    get recipes_path

    assert_redirected_to subscription_path

    assert_equal :expired, @household.reload.subscription_status
    assert_equal 0, @household.pay_subscriptions.count
    assert_equal 0, BillingConsent.count
  end

  private

  def assert_no_checkout(label)
    sessions = []
    original = Stripe::Checkout::Session.method(:create)
    Stripe::Checkout::Session.define_singleton_method(:create) { |params, *| sessions << params }
    ENV["ENABLE_REAL_STRIPE_TESTS"] = "true"
    ENV["STRIPE_SECRET_KEY"] = "sk_test_consent"
    @household.set_payment_processor :stripe, allow_fake: true, processor_id: "cus_checkout"

    assert_no_difference -> { BillingConsent.count }, label do
      assert_no_difference -> { Pay::Subscription.count }, label do
        yield
      end
    end

    assert_redirected_to subscription_path, label
    assert flash[:alert].present?, label
    assert_empty sessions, "#{label}: Stripe Checkout was asked for a session"
  ensure
    Stripe::Checkout::Session.define_singleton_method(:create, original)
  end

  # Subscribes through the Stripe path with the box ticked and returns what
  # the app asked Stripe Checkout for.
  def checkout(plan)
    ENV["ENABLE_REAL_STRIPE_TESTS"] = "true"
    ENV["STRIPE_SECRET_KEY"] = "sk_test_consent"
    @household.set_payment_processor :stripe, allow_fake: true, processor_id: "cus_checkout"
    created = nil
    options = nil
    original = Stripe::Checkout::Session.method(:create)
    Stripe::Checkout::Session.define_singleton_method(:create) do |params, opts = {}|
      created = params
      options = opts
      Stripe::Checkout::Session.construct_from(id: "cs_test_stub", url: "https://checkout.stripe.com/c/pay/cs_test_stub")
    end

    post subscription_path, params: consent_params(plan, household: @household, user: @user)

    assert_redirected_to "https://checkout.stripe.com/c/pay/cs_test_stub"
    @checkout_options = options
    created
  ensure
    Stripe::Checkout::Session.define_singleton_method(:create, original)
  end

  # Answers each Checkout create on the Stripe path with `behavior`, which
  # may take the request options. Yields the params of every create.
  def with_session_create(behavior)
    ENV["ENABLE_REAL_STRIPE_TESTS"] = "true"
    ENV["STRIPE_SECRET_KEY"] = "sk_test_consent"
    @household.set_payment_processor :stripe, allow_fake: true, processor_id: "cus_checkout"
    calls = []
    original = Stripe::Checkout::Session.method(:create)
    Stripe::Checkout::Session.define_singleton_method(:create) do |params, opts = {}|
      calls << params
      behavior.arity.zero? ? behavior.call : behavior.call(opts)
    end
    yield calls
  ensure
    Stripe::Checkout::Session.define_singleton_method(:create, original)
  end

  # Stands in for Stripe on the return from Checkout: the session belongs to
  # this household's customer, and syncing it saves the subscription Checkout
  # started, if it started one.
  def with_checkout_return(subscription_status:, consent:, session_metadata: {})
    household = @household
    original_retrieve = Stripe::Checkout::Session.method(:retrieve)
    original_sync = Pay::Stripe.method(:sync_checkout_session)
    Stripe::Checkout::Session.define_singleton_method(:retrieve) do |*|
      Stripe::Checkout::Session.construct_from(id: "cs_test_stub", customer: "cus_checkout", status: "complete", metadata: session_metadata)
    end
    Pay::Stripe.define_singleton_method(:sync_checkout_session) do |*, **|
      next if subscription_status.nil?

      household.payment_processor.subscriptions.find_or_initialize_by(processor_id: "sub_checkout").update!(
        name: "default", processor_plan: "price_inline", status: subscription_status,
        current_period_start: Time.current, current_period_end: 1.month.from_now,
        metadata: { "billing_consent_id" => consent.id }
      )
    end
    yield
  ensure
    Stripe::Checkout::Session.define_singleton_method(:retrieve, original_retrieve)
    Pay::Stripe.define_singleton_method(:sync_checkout_session, original_sync)
  end

  def stripe_price(**overrides)
    Stripe::Price.construct_from({
      id: "price_test_monthly", object: "price", active: true, currency: "usd", unit_amount: 500,
      type: "recurring", recurring: { interval: "month", interval_count: 1 }
    }.merge(overrides))
  end

  def with_price_retrieve(result)
    original = Stripe::Price.method(:retrieve)
    Stripe::Price.define_singleton_method(:retrieve) { |*| result.is_a?(Exception) ? raise(result) : result }
    yield
  ensure
    Stripe::Price.define_singleton_method(:retrieve, original)
  end

  def sign_in_user(user)
    session_record = user.sessions.create!(token: SecureRandom.hex(32), kind: "browser")
    jar = ActionDispatch::Cookies::CookieJar.build(ActionDispatch::TestRequest.create, {})
    jar.signed[:session_token] = session_record.token
    cookies[:session_token] = jar[:session_token]
  end
end
