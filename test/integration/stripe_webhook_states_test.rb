# frozen_string_literal: true

require "test_helper"

# Posts a real Stripe-Signature header to Pay's webhook, then runs the job Pay
# queues. Stripe retrieve is stubbed with the same object that was signed, so
# the test does not call Stripe and still proves the signed body is what we store.
class StripeWebhookStatesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  SIGNING_SECRET = "whsec_test_signing_secret"

  setup do
    FamilyPlates.config.mode = "hosted"
    @previous_secret = ENV["STRIPE_SIGNING_SECRET"]
    ENV["STRIPE_SIGNING_SECRET"] = SIGNING_SECRET

    @household = households(:one)
    @household.update_columns(created_at: 40.days.ago)
    @customer_id = "cus_webhook_states"
    @household.set_payment_processor(:stripe, allow_fake: true, processor_id: @customer_id)

    @charges = {}
    @subscriptions = {}
    install_retrieve_stubs
  end

  teardown do
    remove_retrieve_stubs
    if @previous_secret
      ENV["STRIPE_SIGNING_SECRET"] = @previous_secret
    else
      ENV.delete("STRIPE_SIGNING_SECRET")
    end
    FamilyPlates.config.reset!
  end

  # @card-23.7
  test "a bad signature is rejected and stores nothing" do
    payload = event_payload("charge.succeeded", charge_object("ch_rejected", "succeeded"))

    assert_no_difference "Pay::Webhook.count" do
      post "/pay/webhooks/stripe", params: payload, headers: {
        "Content-Type" => "application/json",
        "Stripe-Signature" => "t=#{Time.now.to_i},v1=not-a-real-signature"
      }
    end

    assert_response :bad_request
  end

  # @card-23.8
  test "signed charge.succeeded records a paid charge" do
    deliver("charge.succeeded", remember_charge(charge_object("ch_paid", "succeeded", captured: true)))

    assert_equal :paid, state_for("ch_paid").key
  end

  # @card-23.8
  test "signed charge.failed records a failed charge" do
    deliver("charge.failed", remember_charge(charge_object("ch_failed", "failed")))

    assert_equal :failed, state_for("ch_failed").key
  end

  test "signed charge.pending records a pending charge" do
    deliver("charge.pending", remember_charge(charge_object("ch_pending", "pending")))

    assert_equal :pending, state_for("ch_pending").key
  end

  test "signed charge.succeeded with captured false records an uncaptured charge" do
    deliver("charge.succeeded", remember_charge(charge_object("ch_uncaptured", "succeeded", captured: false)))

    assert_equal :uncaptured, state_for("ch_uncaptured").key
  end

  # @card-23.8
  test "signed charge.refunded records a partial refund" do
    deliver("charge.refunded", remember_charge(charge_object("ch_partial", "succeeded", amount_refunded: 100, refunded: false)))

    assert_equal :partially_refunded, state_for("ch_partial").key
  end

  test "signed charge.refunded records a full refund" do
    deliver("charge.refunded", remember_charge(charge_object("ch_refunded", "succeeded", amount_refunded: 400, refunded: true)))

    assert_equal :refunded, state_for("ch_refunded").key
  end

  # @card-23.8
  test "signed charge.dispute.created records the charge as disputed" do
    remember_charge(charge_object("ch_disputed", "succeeded", disputed: true, dispute: "dp_1"))
    dispute = {
      id: "dp_1",
      object: "dispute",
      charge: "ch_disputed",
      status: "needs_response",
      amount: 400,
      currency: "usd"
    }

    deliver("charge.dispute.created", dispute)

    assert_equal :disputed, state_for("ch_disputed").key
    assert_equal "Disputed", state_for("ch_disputed").label
  end

  # @card-23.7
  test "each signed subscription update sets access from the Stripe status" do
    cases = {
      "active" => [ :active, true, 1.month.from_now ],
      "trialing" => [ :trialing, true, 1.month.from_now ],
      "past_due" => [ :past_due_grace, true, 2.days.ago ],
      "incomplete" => [ :incomplete, false, 1.month.from_now ],
      "incomplete_expired" => [ :incomplete_expired, false, 1.month.from_now ],
      "unpaid" => [ :unpaid, false, 1.month.from_now ],
      "paused" => [ :paused, false, 1.month.from_now ]
    }

    cases.each do |stripe_status, (label, entitled, period_end)|
      object = subscription_object("sub_lifecycle", stripe_status, period_end: period_end)
      object[:trial_end] = 10.days.from_now.to_i if stripe_status == "trialing"
      @subscriptions[object[:id]] = object

      deliver("customer.subscription.updated", object)

      assert_equal label, @household.reload.subscription_status, stripe_status
      assert_equal entitled, @household.entitled?, stripe_status
    end
  end

  # @card-23.7
  test "signed subscription.deleted ends access" do
    object = subscription_object("sub_canceled", "canceled", period_end: 1.day.ago)
    object[:ended_at] = 1.hour.ago.to_i
    @subscriptions[object[:id]] = object

    deliver("customer.subscription.deleted", object)

    assert_equal :canceled, @household.reload.subscription_status
    assert_not @household.entitled?
  end

  # @card-23.6
  test "a second signed past_due update removes access after the grace period" do
    object = subscription_object("sub_past_due_late", "past_due", period_end: 10.days.ago)
    @subscriptions[object[:id]] = object

    deliver("customer.subscription.updated", object)

    assert_equal :past_due, @household.reload.subscription_status
    assert_not @household.entitled?
  end

  # The return-URL sync covers a customer who comes back from Checkout. These
  # cover one who closes the tab: the webhooks alone have to grant access.
  test "signed checkout.session.completed grants access for the subscription it names" do
    @subscriptions["sub_from_checkout"] = subscription_object("sub_from_checkout", "active", period_end: 1.month.from_now)
    session = {
      id: "cs_test_closed_tab",
      object: "checkout.session",
      mode: "subscription",
      customer: @customer_id,
      client_reference_id: nil,
      payment_intent: nil,
      subscription: "sub_from_checkout"
    }

    deliver("checkout.session.completed", session)

    assert_equal :active, @household.reload.subscription_status
    assert @household.entitled?
  end

  test "signed customer.subscription.created grants access" do
    object = subscription_object("sub_created", "active", period_end: 1.month.from_now)
    @subscriptions[object[:id]] = object

    deliver("customer.subscription.created", object)

    assert_equal :active, @household.reload.subscription_status
    assert @household.entitled?
  end

  test "signed invoice.payment_failed emails the household's organizer" do
    @household.family_members.find_by!(role: "admin").update!(user: User.create!(email: "organizer@example.com"))
    object = subscription_object("sub_declined", "past_due", period_end: 2.days.ago)
    @subscriptions[object[:id]] = object
    deliver("customer.subscription.updated", object)

    assert_emails 1 do
      deliver("invoice.payment_failed", invoice_object("in_declined", "sub_declined"))
    end

    assert_equal [ @household.email ], ActionMailer::Base.deliveries.last.to
    assert_match "payment was declined", ActionMailer::Base.deliveries.last.body.encoded
  end

  test "signed invoice.payment_failed for a subscription we never saw changes nothing" do
    assert_no_emails do
      deliver("invoice.payment_failed", invoice_object("in_unknown", "sub_unknown"))
    end
  end

  test "signed invoice.updated for the latest invoice re-syncs the subscription" do
    # Pay stores the subscription with latest_invoice expanded.
    object = subscription_object("sub_invoiced", "active", period_end: 1.month.from_now)
      .merge(latest_invoice: invoice_object("in_latest", "sub_invoiced"))
    @subscriptions[object[:id]] = object
    deliver("customer.subscription.created", object)
    assert @household.reload.entitled?

    # Stripe gave up collecting: the invoice update is how the app learns.
    @subscriptions["sub_invoiced"] = subscription_object("sub_invoiced", "unpaid", period_end: 1.month.from_now)
      .merge(latest_invoice: invoice_object("in_latest", "sub_invoiced"))

    deliver("invoice.updated", invoice_object("in_latest", "sub_invoiced"))

    assert_equal :unpaid, @household.reload.subscription_status
    assert_not @household.entitled?
  end

  private

  def invoice_object(id, subscription_id)
    {
      id: id,
      object: "invoice",
      customer: @customer_id,
      status: "open",
      amount_due: 400,
      currency: "usd",
      parent: {
        type: "subscription_details",
        subscription_details: { subscription: subscription_id, metadata: {} }
      },
      lines: { object: "list", data: [], has_more: false }
    }
  end

  def charge_object(id, status, captured: true, amount_refunded: 0, refunded: false, disputed: false, dispute: nil)
    {
      id: id,
      object: "charge",
      customer: @customer_id,
      amount: 400,
      amount_refunded: amount_refunded,
      currency: "usd",
      created: Time.now.to_i,
      status: status,
      captured: captured,
      disputed: disputed,
      refunded: refunded,
      dispute: dispute,
      receipt_url: "https://pay.stripe.com/receipts/#{id}",
      metadata: {},
      payment_method_details: {
        type: "card",
        card: { brand: "visa", last4: "4242", exp_month: 12, exp_year: 2030 }
      }
    }
  end

  def subscription_object(id, status, period_end:)
    {
      id: id,
      object: "subscription",
      customer: @customer_id,
      status: status,
      created: Time.now.to_i,
      metadata: {},
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
            current_period_start: 1.month.ago.to_i,
            current_period_end: period_end.to_i,
            price: { id: "price_monthly", object: "price" }
          }
        ]
      }
    }
  end

  def remember_charge(object)
    @charges[object[:id]] = object
    object
  end

  def deliver(type, object)
    payload = event_payload(type, object)
    timestamp = Time.now
    signature = Stripe::Webhook::Signature.compute_signature(timestamp, payload, SIGNING_SECRET)
    header = Stripe::Webhook::Signature.generate_header(timestamp, signature)

    perform_enqueued_jobs(only: Pay::Webhooks::ProcessJob) do
      post "/pay/webhooks/stripe", params: payload, headers: {
        "Content-Type" => "application/json",
        "Stripe-Signature" => header
      }
    end

    assert_response :ok, response.body
  end

  def event_payload(type, object)
    {
      id: "evt_#{type}_#{object[:id]}",
      object: "event",
      type: type,
      livemode: false,
      api_version: "2026-08-26.dahlia",
      data: { object: object }
    }.to_json
  end

  def state_for(processor_id)
    PayChargeState.for(@household.pay_charges.find_by!(processor_id: processor_id))
  end

  def install_retrieve_stubs
    charges = @charges
    subscriptions = @subscriptions

    Stripe::Charge.singleton_class.alias_method :retrieve_without_webhook_stub, :retrieve
    Stripe::Subscription.singleton_class.alias_method :retrieve_without_webhook_stub, :retrieve

    Stripe::Charge.define_singleton_method(:retrieve) do |params, *_rest|
      id = params.is_a?(Hash) ? (params[:id] || params["id"]) : params
      Stripe::Charge.construct_from(charges.fetch(id))
    end

    Stripe::Subscription.define_singleton_method(:retrieve) do |params, *_rest|
      id = params.is_a?(Hash) ? (params[:id] || params["id"]) : params
      Stripe::Subscription.construct_from(subscriptions.fetch(id))
    end
  end

  def remove_retrieve_stubs
    Stripe::Charge.singleton_class.alias_method :retrieve, :retrieve_without_webhook_stub
    Stripe::Subscription.singleton_class.alias_method :retrieve, :retrieve_without_webhook_stub
  end
end
