# frozen_string_literal: true

require "test_helper"

# A billing owner who closes the tab after paying never comes back through
# the return URL; the signed webhooks alone have to confirm their consent and
# send the acknowledgment, exactly once however often Stripe delivers.
# Stripe's retrieve is stubbed with the signed object, as in
# StripeWebhookStatesTest.
class BillingConsentWebhookTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include BillingConsentTestHelper

  SIGNING_SECRET = "whsec_test_billing_consent"

  setup do
    FamilyPlates.config.mode = "hosted"
    @previous_secret = ENV["STRIPE_SIGNING_SECRET"]
    ENV["STRIPE_SIGNING_SECRET"] = SIGNING_SECRET

    @household = households(:one)
    @user = User.create!(email: "owner@webhook.test")
    @household.update!(billing_owner: @user)
    @customer_id = "cus_billing_consent"
    @household.set_payment_processor(:stripe, allow_fake: true, processor_id: @customer_id)
    @consent = BillingConsent.record!(BillingOffer.for(:monthly), household: @household, user: @user)
    @consent.update!(checkout_session_id: "cs_test_closed_tab", checkout_state: "open")

    @subscriptions = {}
    Stripe::Subscription.singleton_class.alias_method :retrieve_without_consent_stub, :retrieve
    subscriptions = @subscriptions
    Stripe::Subscription.define_singleton_method(:retrieve) do |params, *_rest|
      id = params.is_a?(Hash) ? (params[:id] || params["id"]) : params
      Stripe::Subscription.construct_from(subscriptions.fetch(id))
    end
  end

  teardown do
    Stripe::Subscription.singleton_class.alias_method :retrieve, :retrieve_without_consent_stub
    @previous_secret ? ENV["STRIPE_SIGNING_SECRET"] = @previous_secret : ENV.delete("STRIPE_SIGNING_SECRET")
    FamilyPlates.config.reset!
  end

  test "checkout.session.completed alone confirms the consent and queues one acknowledgment" do
    remember(subscription_object("sub_closed_tab", "active"))

    assert_enqueued_jobs 1, only: BillingConsentAcknowledgmentJob do
      deliver("checkout.session.completed", checkout_session("sub_closed_tab"))
    end

    @consent.reload
    assert @consent.confirmed?
    assert_equal "sub_closed_tab", @consent.subscription_processor_id
    assert @household.reload.entitled?

    with_stripe_payment("sub_closed_tab", amount_paid: 500) do
      assert_emails(1) { perform_enqueued_jobs(only: BillingConsentAcknowledgmentJob) }
    end
    assert_equal [ @user.email ], ActionMailer::Base.deliveries.last.to
    assert_equal 500, @consent.reload.paid_amount_minor_units
  end

  test "replayed and overlapping webhooks never queue a second acknowledgment" do
    object = remember(subscription_object("sub_replayed", "active"))

    assert_enqueued_jobs 1, only: BillingConsentAcknowledgmentJob do
      deliver("customer.subscription.created", object, event_id: "evt_created_once")
      deliver("customer.subscription.created", object, event_id: "evt_created_once")
      deliver("checkout.session.completed", checkout_session("sub_replayed"))
      deliver("customer.subscription.updated", object)
    end

    with_stripe_payment("sub_replayed", amount_paid: 500) do
      assert_emails(1) { perform_enqueued_jobs(only: BillingConsentAcknowledgmentJob) }
    end

    # A late redelivery after the email went out sends nothing either.
    deliver("customer.subscription.updated", object)
    BillingConsent.retry_unsent_acknowledgments
    assert_no_emails do
      perform_enqueued_jobs(only: BillingConsentAcknowledgmentJob)
      BillingConsent.recover!
    end
  end

  test "checkout.session.completed settles an attempt whose create answer was lost, on the same consent" do
    @consent.update_columns(checkout_session_id: nil, checkout_state: "unknown")
    remember(subscription_object("sub_lost_answer", "active"))

    assert_no_difference -> { BillingConsent.count } do
      assert_enqueued_jobs 1, only: BillingConsentAcknowledgmentJob do
        deliver("checkout.session.completed", checkout_session("sub_lost_answer"))
      end
    end

    @consent.reload
    assert_equal [ "confirmed", "cs_test_closed_tab", "sub_lost_answer" ],
      [ @consent.checkout_state, @consent.checkout_session_id, @consent.subscription_processor_id ]
    assert @household.reload.entitled?
  end

  test "checkout.session.expired releases the household's attempt" do
    deliver("checkout.session.expired", checkout_session(nil).merge(status: "expired", payment_status: "unpaid"))

    assert_equal "expired", @consent.reload.checkout_state
    assert_not @consent.confirmed?
    assert BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
  end

  test "a Checkout session for another household's customer settles nothing" do
    @consent.update_columns(checkout_session_id: nil, checkout_state: "unknown")

    deliver("checkout.session.expired", checkout_session(nil).merge(status: "expired", customer: "cus_someone_else"))

    assert_equal [ "unknown", nil ], [ @consent.reload.checkout_state, @consent.checkout_session_id ]
  end

  test "a subscription that is not active yet confirms nothing until Stripe reports it paid" do
    remember(subscription_object("sub_incomplete", "incomplete"))

    assert_no_enqueued_jobs only: BillingConsentAcknowledgmentJob do
      deliver("checkout.session.completed", checkout_session("sub_incomplete"))
    end
    assert_not @consent.reload.confirmed?

    paid = remember(subscription_object("sub_incomplete", "active"))
    assert_enqueued_jobs 1, only: BillingConsentAcknowledgmentJob do
      deliver("customer.subscription.updated", paid)
    end
    assert @consent.reload.confirmed?
  end

  test "another household's subscription naming this consent does not confirm it" do
    other = households(:two)
    other.set_payment_processor(:stripe, allow_fake: true, processor_id: "cus_other_household")
    object = remember(subscription_object("sub_other_household", "active").merge(customer: "cus_other_household"))

    assert_no_enqueued_jobs only: BillingConsentAcknowledgmentJob do
      deliver("customer.subscription.created", object)
    end

    assert_not @consent.reload.confirmed?
    assert other.reload.active_subscription?, "the other household's own access is unaffected"
  end

  test "a subscription at a different Stripe price than the one agreed to is not acknowledged" do
    @consent.update!(stripe_price_id: "price_agreed")
    object = remember(subscription_object("sub_other_price", "active"))

    assert_no_enqueued_jobs only: BillingConsentAcknowledgmentJob do
      deliver("customer.subscription.created", object)
    end

    assert_not @consent.reload.confirmed?
  end

  private

  def remember(object)
    @subscriptions[object[:id]] = object
  end

  def checkout_session(subscription_id)
    {
      id: "cs_test_closed_tab", object: "checkout.session", mode: "subscription", status: "complete",
      payment_status: "paid", customer: @customer_id, client_reference_id: nil, payment_intent: nil,
      subscription: subscription_id, metadata: { billing_consent_id: @consent.id }
    }
  end

  def subscription_object(id, status)
    {
      id: id,
      object: "subscription",
      customer: @customer_id,
      status: status,
      created: Time.now.to_i,
      metadata: { billing_consent_id: @consent.id },
      cancel_at_period_end: false,
      items: {
        object: "list",
        has_more: false,
        url: "/v1/subscription_items",
        data: [
          {
            id: "si_#{id}",
            object: "subscription_item",
            quantity: 1,
            current_period_start: Time.now.to_i,
            current_period_end: 1.month.from_now.to_i,
            price: { id: "price_monthly", object: "price", unit_amount: 500 }
          }
        ]
      }
    }
  end

  def deliver(type, object, event_id: nil)
    @event_sequence = @event_sequence.to_i + 1
    payload = {
      id: event_id || "evt_#{type}_#{object[:id]}_#{@event_sequence}",
      object: "event",
      type: type,
      livemode: false,
      api_version: "2026-08-26.dahlia",
      data: { object: object }
    }.to_json
    timestamp = Time.now
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, SIGNING_SECRET)

    perform_enqueued_jobs(only: Pay::Webhooks::ProcessJob) do
      post "/pay/webhooks/stripe", params: payload, headers: {
        "Content-Type" => "application/json",
        "Stripe-Signature" => Stripe::Webhook::Signature.generate_header(timestamp, signature)
      }
    end

    assert_response :ok, response.body
  end
end
