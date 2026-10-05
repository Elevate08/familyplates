# frozen_string_literal: true

require "test_helper"

# Hosted billing email comes from Pay's mailer, through the app's own SMTP,
# to the household's billing owner. Drives Pay's real Stripe webhook handlers
# with Stripe's objects stubbed, so nothing calls Stripe or a mail server.
class PayBillingEmailsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include BillingConsentTestHelper

  setup do
    FamilyPlates.config.reset!
    FamilyPlates.config.mode = "hosted"
    ActionMailer::Base.deliveries.clear

    @household = households(:one)
    @household.set_payment_processor(:stripe, allow_fake: true, processor_id: "cus_pay_mail")
    @owner = User.create!(email: "billing-owner@pay-mail.test", **accepted_terms)
    @household.update_columns(billing_owner_user_id: @owner.id)
    # Household#email, the old recipient and today's fallback: the first organizer's account.
    @organizer = User.create!(email: "organizer@pay-mail.test", **accepted_terms)
    @household.family_members.find_by!(role: "admin").update_columns(user_id: @organizer.id)
    @subscription = @household.payment_processor.subscriptions.create!(
      name: "default", processor_id: "sub_pay_mail", processor_plan: "price_annual", quantity: 1, status: "active"
    )
  end

  teardown { FamilyPlates.config.reset! }

  test "Pay is configured for FamilyPlates and sends through the app's mailer" do
    assert_equal "FamilyPlates", Pay.application_name
    assert_equal BillingOffer::SUPPORT_EMAIL, Pay.support_email.address
    assert_nil Pay.business_name, "no company exists to name"
    assert_nil Pay.business_address
    assert_operator Pay::UserMailer, :<, ApplicationMailer

    %i[receipt refund payment_failed payment_action_required].each { |e| assert Pay.send_email?(e), "#{e} should be on" }
    assert_not Pay.send_email?(:subscription_trial_will_end, @subscription)
    assert_not Pay.send_email?(:subscription_trial_ended, @subscription)
  end

  test "receipt goes to the billing owner, from the app's address" do
    deliver_charge_event("charge.succeeded", Pay::Stripe::Webhooks::ChargeSucceeded)

    mail = sole_mail
    assert_equal [ @owner.email ], mail.to
    assert_not_equal @household.email, @owner.email
    assert_equal [ ENV.fetch("MAILER_DEFAULT_FROM", "noreply@familyplates.app") ], mail.from
  end

  test "refund goes to the billing owner" do
    deliver_charge_event("charge.refunded", Pay::Stripe::Webhooks::ChargeRefunded, amount_refunded: 400)

    assert_equal [ @owner.email ], sole_mail.to
  end

  test "payment failed goes to the billing owner" do
    deliver_invoice_event("invoice.payment_failed", Pay::Stripe::Webhooks::PaymentFailed)

    assert_equal [ @owner.email ], sole_mail.to
  end

  test "payment action required goes to the billing owner" do
    deliver_action_required

    mail = sole_mail
    assert_equal [ @owner.email ], mail.to
    assert_includes mail.text_part.body.to_s, "pi_action"
  end

  test "annual renewal reminder goes to the billing owner" do
    deliver_renewal_event("year")

    assert_equal [ @owner.email ], sole_mail.to
  end

  test "a monthly renewal sends no reminder" do
    deliver_renewal_event("month")

    assert_empty ActionMailer::Base.deliveries
  end

  test "without a billing owner, every email falls back to the household's first organizer" do
    @household.update_columns(billing_owner_user_id: nil)
    fallback = @organizer.email
    assert_equal fallback, @household.reload.email

    deliver_invoice_event("invoice.payment_failed", Pay::Stripe::Webhooks::PaymentFailed)
    deliver_charge_event("charge.succeeded", Pay::Stripe::Webhooks::ChargeSucceeded)
    deliver_renewal_event("year")

    assert_equal 3, ActionMailer::Base.deliveries.size
    assert_equal [ [ fallback ] ], ActionMailer::Base.deliveries.map(&:to).uniq
  end

  test "Stripe's trial emails are never sent, on trial or after it" do
    perform_enqueued_jobs do
      [ [ "trialing", 3.days.from_now ], [ "active", 1.day.ago ] ].each do |status, trial_end|
        object = stripe_subscription(status, trial_end: trial_end.to_i)
        @subscription.update!(status: status, trial_ends_at: trial_end)
        stubbing(Stripe::Subscription, :retrieve, object) do
          Pay::Stripe::Webhooks::SubscriptionTrialWillEnd.new.call(event("customer.subscription.trial_will_end", object))
        end
      end
    end

    assert_empty ActionMailer::Base.deliveries
  end

  test "the receipt states the charge, points questions at support, and names no company" do
    deliver_charge_event("charge.succeeded", Pay::Stripe::Webhooks::ChargeSucceeded)

    mail = sole_mail
    bodies(mail).each do |body|
      assert_includes body, "$4.00"
      assert_includes body, "Visa (**** **** **** 4242)"
      assert_includes body, BillingOffer::SUPPORT_EMAIL
      assert_no_match(/reply to this email/i, body, "the sender address is not monitored")
    end
    assert_includes mail.text_part.body.to_s, BillingOffer::REFUND_REQUEST
  end

  test "the refund email makes no timing promise" do
    deliver_charge_event("charge.refunded", Pay::Stripe::Webhooks::ChargeRefunded, amount_refunded: 400)

    bodies(sole_mail).each do |body|
      assert_includes body, "$4.00"
      assert_includes body, BillingOffer::SUPPORT_EMAIL
      assert_no_match(/7 business days|reply to this email/i, body)
    end
  end

  test "the failed payment email sends the owner to the subscription page and states the grace period" do
    deliver_invoice_event("invoice.payment_failed", Pay::Stripe::Webhooks::PaymentFailed)

    bodies(sole_mail).each do |body|
      assert_includes body, "http://example.com/subscription"
      assert_includes body, "#{Household::Billing::PAST_DUE_GRACE_DAYS} days"
      assert_includes body, BillingOffer::SUPPORT_EMAIL
      assert_no_match(/hit reply/i, body)
    end
  end

  test "the action-required email points at support, not a reply" do
    deliver_action_required

    bodies(sole_mail).each do |body|
      assert_includes body, BillingOffer::SUPPORT_EMAIL
      assert_no_match(/hit reply/i, body)
    end
  end

  test "the annual renewal email states the date, the amount and how to cancel" do
    deliver_renewal_event("year")

    bodies(sole_mail).each do |body|
      assert_includes body, "November 5, 2026"
      assert_includes body, "$50"
      assert_includes body, "http://example.com/subscription"
      assert_match(/cancel/i, body)
      assert_match(/until the end of the period you have paid for/, body)
      assert_includes body, BillingOffer::SUPPORT_EMAIL
      assert_no_match(/hit reply/i, body)
    end
  end

  private

  # Minitest 6 no longer ships stub. Replaces a Stripe class method for the block.
  def stubbing(klass, name, result)
    original = klass.method(name)
    klass.define_singleton_method(name) { |*, **| result }
    yield
  ensure
    klass.define_singleton_method(name, original)
  end

  def sole_mail
    assert_equal 1, ActionMailer::Base.deliveries.size
    ActionMailer::Base.deliveries.last
  end

  def bodies(mail)
    [ mail.text_part.body.to_s, mail.html_part.body.to_s ]
  end

  def event(type, object)
    Stripe::Event.construct_from(id: "evt_#{type}", object: "event", type: type, data: { object: object })
  end

  def deliver_charge_event(type, handler, amount_refunded: 0)
    charge = Stripe::Charge.construct_from(
      id: "ch_pay_mail", object: "charge", customer: "cus_pay_mail", amount: 400, amount_refunded: amount_refunded,
      currency: "usd", created: Time.now.to_i, status: "succeeded", captured: true, refunded: amount_refunded.positive?,
      receipt_url: "https://pay.stripe.com/receipts/ch_pay_mail", metadata: {},
      payment_method_details: { type: "card", card: { brand: "visa", last4: "4242", exp_month: 12, exp_year: 2030 } }
    )
    stubbing(Stripe::Charge, :retrieve, charge) do
      perform_enqueued_jobs { handler.new.call(event(type, charge)) }
    end
  end

  def invoice
    Stripe::Invoice.construct_from(
      id: "in_pay_mail", object: "invoice", customer: "cus_pay_mail",
      parent: { subscription_details: { subscription: "sub_pay_mail" } },
      next_payment_attempt: Time.utc(2026, 11, 5, 12).to_i,
      lines: { object: "list", has_more: false, url: "/v1/lines", data: [ { pricing: { price_details: { price: "price_annual" } } } ] }
    )
  end

  def deliver_invoice_event(type, handler)
    perform_enqueued_jobs { handler.new.call(event(type, invoice)) }
  end

  def deliver_action_required
    invoice_payment = Stripe::InvoicePayment.construct_from(id: "inpay_1", payment: { payment_intent: "pi_action" })
    stubbing(Stripe::InvoicePayment, :list, [ invoice_payment ]) do
      deliver_invoice_event("invoice.payment_action_required", Pay::Stripe::Webhooks::PaymentActionRequired)
    end
  end

  def deliver_renewal_event(interval)
    price = Stripe::Price.construct_from(id: "price_annual", type: "recurring", recurring: { interval: interval })
    stubbing(Stripe::Price, :retrieve, price) do
      perform_enqueued_jobs { Pay::Stripe::Webhooks::SubscriptionRenewing.new.call(event("invoice.upcoming", invoice)) }
    end
  end

  def stripe_subscription(status, trial_end:)
    Stripe::Subscription.construct_from(
      id: "sub_pay_mail", object: "subscription", customer: "cus_pay_mail", status: status, created: Time.now.to_i,
      metadata: {}, cancel_at_period_end: false, trial_end: trial_end,
      items: { object: "list", has_more: false, url: "/v1/items", data: [ { id: "si_1", object: "subscription_item", quantity: 1,
        current_period_start: 1.month.ago.to_i, current_period_end: 1.month.from_now.to_i,
        price: { id: "price_annual", object: "price" } } ] }
    )
  end
end
