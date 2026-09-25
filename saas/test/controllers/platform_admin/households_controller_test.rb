require "test_helper"

class PlatformAdmin::HouseholdsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = PlatformAdminAccount.create!(
      email: "operator@example.com",
      password: "correct horse battery staple",
      otp_secret: "JBSWY3DPEHPK3PXP"
    )
    @alpha = households(:one)
    @beta = Household.create!(name: "Miller Family")
    @alpha.update!(name: "Alpha Kitchen")
    @beta.update!(name: "Beta Kitchen")
    @alpha.family_members.first.update!(user: User.create!(email: "alpha@example.com"))
    @beta.family_members.create!(name: "Beta Admin", role: "admin", pin: "1234", user: User.create!(email: "beta@example.com"))
    sign_in_platform_admin(@admin)
  end

  teardown do
    FamilyPlates.config.reset!
  end

  test "the status filter has an accessible name" do
    get platform_admin_households_path

    assert_select "select#status[aria-label='Status']"
  end

  # @card-44.1
  test "lists household metadata and lifecycle info" do
    get platform_admin_households_path

    assert_response :success
    assert_select "h1", text: /Households/i
    assert_includes response.body, "Alpha Kitchen"
    assert_includes response.body, "Beta Kitchen"
    assert_includes response.body, "Joined"
    assert_includes response.body, "Promotion"
  end

  # @card-44.2
  test "searches by household name or customer email" do
    get platform_admin_households_path, params: { search: "beta@example.com" }

    assert_response :success
    assert_includes response.body, "Beta Kitchen"
    assert_not_includes response.body, "Alpha Kitchen"
  end

  # @card-44.3
  test "shows privacy-safe household details" do
    get platform_admin_household_path(@alpha)

    assert_response :success
    assert_select "h1", text: "Alpha Kitchen"
    assert_includes response.body, "Members"
    assert_includes response.body, "Recipes"
    assert_includes response.body, "Recent household activity"
    assert_not_includes response.body, @alpha.join_code
  end

  # @card-42.1
  test "operator sees every Stripe charge state on that household only" do
    customer = @alpha.set_payment_processor(:fake_processor, allow_fake: true)
    other = @beta.set_payment_processor(:fake_processor, allow_fake: true)

    {
      "ch_paid" => { "status" => "succeeded", "captured" => true },
      "ch_failed" => { "status" => "failed" },
      "ch_pending" => { "status" => "pending" },
      "ch_uncaptured" => { "status" => "succeeded", "captured" => false },
      "ch_partial" => { "status" => "succeeded", "captured" => true },
      "ch_refunded" => { "status" => "succeeded", "refunded" => true },
      "ch_disputed" => { "status" => "succeeded", "disputed" => true, "dispute" => "dp_1" }
    }.each do |processor_id, object|
      refunded = processor_id == "ch_partial" ? 100 : (processor_id == "ch_refunded" ? 400 : 0)
      customer.charges.create!(processor_id: processor_id, amount: 400, amount_refunded: refunded, currency: "usd", object: object)
    end
    other.charges.create!(processor_id: "ch_other_household", amount: 900, currency: "usd", object: { "status" => "succeeded" })

    get platform_admin_household_path(@alpha)

    assert_response :success
    assert_select "[data-charge-state=paid]", text: "Paid"
    assert_select "[data-charge-state=failed]", text: "Failed"
    assert_select "[data-charge-state=pending]", text: "Pending"
    assert_select "[data-charge-state=uncaptured]", text: "Uncaptured"
    assert_select "[data-charge-state=partially_refunded]", text: "Partially refunded"
    assert_select "[data-charge-state=refunded]", text: "Refunded"
    assert_select "[data-charge-state=disputed]", text: "Disputed"
    assert_not_includes response.body, "ch_other_household"

    get platform_admin_household_path(@beta)
    assert_select "[data-charge-state=paid]", text: "Paid", count: 1
    assert_select "[data-charge-state=disputed]", count: 0
  end

  # @card-42.1
  test "operator list shows each household subscription state and stops after one page" do
    FamilyPlates.config.mode = "hosted"
    @alpha.update_columns(created_at: 40.days.ago)
    @beta.update_columns(created_at: 40.days.ago)

    states = {
      "Active Kitchen" => "active",
      "Trial Kitchen" => "trialing",
      "Unpaid Kitchen" => "unpaid",
      "Paused Kitchen" => "paused",
      "Incomplete Kitchen" => "incomplete",
      "Lapsed Kitchen" => "incomplete_expired"
    }
    states.each do |name, status|
      household = Household.create!(name: name)
      household.update_columns(created_at: 40.days.ago)
      household.set_payment_processor :fake_processor, allow_fake: true
      household.payment_processor.subscriptions.create!(
        name: "default",
        processor_id: "sub_#{status}",
        processor_plan: "monthly",
        status: status,
        current_period_start: Time.current,
        current_period_end: 1.month.from_now
      )
    end

    get platform_admin_households_path

    assert_response :success
    assert_select "[data-subscription-status=active]", text: "Active"
    assert_select "[data-subscription-status=trialing]"
    assert_select "[data-subscription-status=unpaid]", text: "Unpaid"
    assert_select "[data-subscription-status=paused]", text: "Paused"
    assert_select "[data-subscription-status=incomplete]", text: "Incomplete"
    assert_select "[data-subscription-status=incomplete_expired]", text: "Incomplete expired"
    assert_includes response.body, "Active Kitchen"
    assert_includes response.body, "Unpaid Kitchen"

    extra = PlatformAdmin::HouseholdsController::PAGE_SIZE
    extra.times { |index| Household.create!(name: "Paged Kitchen #{index}") }
    assert_operator Household.count, :>, PlatformAdmin::HouseholdsController::PAGE_SIZE

    get platform_admin_households_path
    assert_select "a[href^='/platform_admin/households/']", count: PlatformAdmin::HouseholdsController::PAGE_SIZE
  end

  # @card-47.4
  test "operator can suspend and restore a household" do
    post suspend_platform_admin_household_path(@alpha), params: { reason: "Support review" }
    assert_redirected_to platform_admin_household_path(@alpha)
    assert_equal "Support review", @alpha.reload.suspension_reason

    post restore_platform_admin_household_path(@alpha)
    assert_redirected_to platform_admin_household_path(@alpha)
    assert_not @alpha.reload.suspended?
  end

  test "operator cancels a subscription at period end and the household keeps access until then" do
    sub = subscribe(@alpha)

    post cancel_subscription_platform_admin_household_path(@alpha), params: { when: "period_end", reason: "Customer asked by email" }

    assert_redirected_to platform_admin_household_path(@alpha)
    assert_match "Subscription will end on", flash[:notice]
    assert sub.reload.ends_at.present?
    assert @alpha.reload.active_subscription?
    assert_billing_audit "household.subscription_canceled", reason: "Customer asked by email", "immediately" => false
  end

  test "operator cancels a subscription now and access ends" do
    FamilyPlates.config.mode = "hosted"
    sub = subscribe(@alpha)

    post cancel_subscription_platform_admin_household_path(@alpha), params: { when: "now", reason: "Chargeback" }

    assert_equal "Subscription canceled; access has ended.", flash[:notice]
    assert_equal "canceled", sub.reload.status
    assert_not @alpha.reload.entitled?
  end

  test "cancelling a household with no subscription says so" do
    post cancel_subscription_platform_admin_household_path(@alpha), params: { when: "now", reason: "Tidy up" }

    assert_equal "No active subscription to cancel.", flash[:alert]
  end

  test "operator refunds what is left of a charge by default" do
    charge = charge(@alpha, amount: 3500)

    post refund_charge_platform_admin_household_path(@alpha, charge_id: charge.id), params: { reason: "Double billed" }

    assert_equal "Refunded $35.00.", flash[:notice]
    assert_equal 3500, charge.reload.amount_refunded
    assert_billing_audit "household.charge_refunded", reason: "Double billed", "amount_cents" => 3500
  end

  test "operator refunds part of a charge" do
    charge = charge(@alpha, amount: 3500)

    post refund_charge_platform_admin_household_path(@alpha, charge_id: charge.id), params: { amount: "$10.50", reason: "Goodwill" }

    assert_equal "Refunded $10.50.", flash[:notice]
    assert_equal 1050, charge.reload.amount_refunded
  end

  test "a refund larger than what is left, or not a number, is refused" do
    charge = charge(@alpha, amount: 400)
    charge.update!(amount_refunded: 100)

    post refund_charge_platform_admin_household_path(@alpha, charge_id: charge.id), params: { amount: "3.01", reason: "Too much" }
    assert_equal "A refund must be between $0.01 and $3.00.", flash[:alert]

    post refund_charge_platform_admin_household_path(@alpha, charge_id: charge.id), params: { amount: "four", reason: "Typo" }
    assert_equal "Enter the refund as a dollar amount, like 4.00.", flash[:alert]

    assert_equal 100, charge.reload.amount_refunded
  end

  test "a charge can only be refunded through the household it belongs to" do
    charge = charge(@beta, amount: 400)

    post refund_charge_platform_admin_household_path(@alpha, charge_id: charge.id), params: { reason: "Wrong household" }

    assert_response :not_found
    assert_equal 0, charge.reload.amount_refunded.to_i
  end

  test "comping a household that is not paying extends its free trial" do
    travel_to Time.zone.local(2026, 9, 1) do
      @alpha.update!(trial_extended_until: 5.days.from_now)

      post comp_platform_admin_household_path(@alpha), params: { months: "2", reason: "Beta tester" }

      assert_equal 5.days.from_now + 2.months, @alpha.reload.trial_extended_until
      assert_match "Free trial extended to", flash[:notice]
      assert_billing_audit "household.comped", reason: "Beta tester", "months" => 2, "applied_to" => "trial"
    end
  end

  test "comping a household whose trial ran out starts the free months today" do
    freeze_time do
      post comp_platform_admin_household_path(@alpha), params: { months: "1", reason: "Apology" }

      assert_equal 1.month.from_now, @alpha.reload.trial_extended_until
    end
  end

  test "comping a paying household moves its next Stripe charge back by the months given" do
    freeze_time do
      renews_at = 20.days.from_now
      @alpha.set_payment_processor :stripe, allow_fake: true, processor_id: "cus_comp"
      sub = @alpha.payment_processor.subscriptions.create!(
        name: "default", processor_id: "sub_comp", processor_plan: "annual", status: "active",
        current_period_start: Time.current, current_period_end: renews_at
      )
      update = stub_stripe_comp(trial_end: renews_at + 3.months) do
        post comp_platform_admin_household_path(@alpha), params: { months: "3", reason: "Outage credit" }
      end

      assert_equal [ "sub_comp", { trial_end: (renews_at + 3.months).to_i, proration_behavior: "none" } ], update
      assert_equal "3 free months applied; the next charge is on #{(renews_at + 3.months).to_date.to_formatted_s(:long)}.", flash[:notice]
      assert_nil @alpha.reload.trial_extended_until
      assert sub.reload.active?
      assert_billing_audit "household.comped", reason: "Outage credit", "months" => 3, "applied_to" => "subscription"
    end
  end

  test "comp months outside one to twelve are refused" do
    [ "0", "13", "", "two" ].each do |months|
      post comp_platform_admin_household_path(@alpha), params: { months: months, reason: "Typo" }

      assert_equal "Comp between 1 and 12 months.", flash[:alert], months.inspect
    end
    assert_nil @alpha.reload.trial_extended_until
  end

  test "billing changes need a reason for the audit log" do
    charge = charge(@alpha, amount: 400)

    post refund_charge_platform_admin_household_path(@alpha, charge_id: charge.id), params: { reason: "  " }

    assert_equal "Give a reason; it goes in the audit log.", flash[:alert]
    assert_equal 0, charge.reload.amount_refunded.to_i
  end

  test "support operators see billing but cannot change it" do
    support = PlatformAdminAccount.create!(email: "support@example.com", password: "correct horse battery staple", role: "support")
    sign_in_platform_admin(support)
    subscribe(@alpha)
    charge = charge(@alpha, amount: 400)

    get platform_admin_household_path(@alpha)
    assert_select "form[action$='/comp']", count: 0
    assert_select "form[action$='/refund']", count: 0
    assert_select "form[action$='/cancel_subscription']", count: 0

    post refund_charge_platform_admin_household_path(@alpha, charge_id: charge.id), params: { reason: "Trying" }
    assert_equal "Only owner and billing operators can change a household's billing.", flash[:alert]
    assert_equal 0, charge.reload.amount_refunded.to_i

    post cancel_subscription_platform_admin_household_path(@alpha), params: { when: "now", reason: "Trying" }
    assert @alpha.reload.active_subscription?
  end

  test "owner operators see the billing controls" do
    subscribe(@alpha)
    charge(@alpha, amount: 400)

    get platform_admin_household_path(@alpha)

    assert_select "form[action$='/comp']", count: 1
    assert_select "form[action$='/refund']", count: 1
    assert_select "form[action$='/cancel_subscription']", count: 1
  end

  private

  def subscribe(household)
    household.set_payment_processor :fake_processor, allow_fake: true
    household.payment_processor.subscriptions.create!(
      name: "default", processor_id: "sub_#{SecureRandom.hex(4)}", processor_plan: "monthly", status: "active",
      current_period_start: Time.current, current_period_end: 1.month.from_now
    )
  end

  def charge(household, amount:)
    household.set_payment_processor :fake_processor, allow_fake: true unless household.payment_processor
    household.payment_processor.charges.create!(processor_id: "ch_#{SecureRandom.hex(4)}", amount: amount, amount_refunded: 0)
  end

  # Stands in for Stripe: records the update a comp sends, and answers the
  # sync that follows with the subscription Stripe would then hold.
  def stub_stripe_comp(trial_end:)
    sent = nil
    originals = { update: Stripe::Subscription.method(:update), retrieve: Stripe::Subscription.method(:retrieve) }
    Stripe::Subscription.define_singleton_method(:update) do |id, params, *|
      sent = [ id, params ]
      Stripe::Subscription.construct_from(id: id)
    end
    Stripe::Subscription.define_singleton_method(:retrieve) do |*|
      Stripe::Subscription.construct_from(
        id: "sub_comp", object: "subscription", customer: "cus_comp", status: "trialing", created: Time.current.to_i,
        metadata: {}, cancel_at_period_end: false, trial_end: trial_end.to_i, trial_start: Time.current.to_i,
        items: { object: "list", has_more: false, url: "/v1/subscription_items", data: [
          { id: "si_comp", object: "subscription_item", quantity: 1, current_period_start: Time.current.to_i,
            current_period_end: trial_end.to_i, price: { id: "price_annual", object: "price" } }
        ] }
      )
    end
    yield
    sent
  ensure
    Stripe::Subscription.define_singleton_method(:update, originals[:update])
    Stripe::Subscription.define_singleton_method(:retrieve, originals[:retrieve])
  end

  def assert_billing_audit(action, reason:, **metadata)
    event = PlatformAuditEvent.where(action: action, target_id: @alpha.id).last
    assert event, "no #{action} audit event"
    assert_equal reason, event.metadata["reason"]
    metadata.each { |key, value| assert_equal value, event.metadata[key.to_s], key }
  end

  def sign_in_platform_admin(admin)
    post platform_admin_session_path, params: {
      email: admin.email,
      password: "correct horse battery staple",
      otp_code: PlatformAdminAccount::Totp.code(admin.otp_secret)
    }
  end
end
