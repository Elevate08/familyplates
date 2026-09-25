# frozen_string_literal: true

require "test_helper"

class SubscriptionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    FamilyPlates.config.reset!
    @admin = family_members(:one)
    @member = family_members(:two)
    @user = User.create!(email: "admin@household.test")
    @admin.update!(user: @user)
    @member_user = User.create!(email: "member@household.test")
    @member.update!(user: @member_user)

    sign_in_user(@user)
    sign_in_as(@admin)
  end

  teardown do
    FamilyPlates.config.reset!
  end

  # @card-23.3
  test "show in appliance mode redirects to root" do
    FamilyPlates.config.mode = "appliance"
    get subscription_path
    assert_redirected_to root_path
    assert_equal "Subscriptions are only enabled in hosted mode.", flash[:notice]
  end

  # @card-23.9
  test "show in hosted mode renders subscription dashboard" do
    FamilyPlates.config.mode = "hosted"
    get subscription_path
    assert_response :success
    assert_select "h1", text: /Subscription & Billing/i
    assert_select "button, input[type=submit]", text: /Subscribe/i
  end

  # @card-23.10
  test "returning from Stripe Checkout syncs the session Pay named in the return URL" do
    FamilyPlates.config.mode = "hosted"
    household = @admin.household
    household.set_payment_processor :stripe, allow_fake: true, processor_id: "cus_returned"
    synced = []
    original = Pay::Stripe.method(:sync_checkout_session)
    original_retrieve = Stripe::Checkout::Session.method(:retrieve)
    Stripe::Checkout::Session.define_singleton_method(:retrieve) do |*|
      Stripe::Checkout::Session.construct_from(id: "cs_test_returned", customer: "cus_returned")
    end
    # Stands in for Stripe: what a completed Checkout leaves behind once synced.
    Pay::Stripe.define_singleton_method(:sync_checkout_session) do |session_id, **|
      synced << session_id
      household.payment_processor.subscriptions.create!(
        name: "default", processor_id: "sub_returned", processor_plan: "annual",
        status: "active", current_period_start: Time.current, current_period_end: 1.year.from_now
      )
    end

    # Pay appends stripe_checkout_session_id={CHECKOUT_SESSION_ID} to the
    # success_url; this is the request Stripe sends the customer back with.
    get subscription_path(success: true, stripe_checkout_session_id: "cs_test_returned")

    assert_equal [ "cs_test_returned" ], synced
    assert household.reload.active_subscription?
    assert_match "Thank you for subscribing", flash[:notice]
  ensure
    Pay::Stripe.define_singleton_method(:sync_checkout_session, original)
    Stripe::Checkout::Session.define_singleton_method(:retrieve, original_retrieve) if original_retrieve
  end

  # @card-21.4 @card-23.10
  test "a checkout return for another household's session is not synced" do
    FamilyPlates.config.mode = "hosted"
    household = @admin.household
    household.set_payment_processor :stripe, allow_fake: true, processor_id: "cus_mine"
    synced = []
    original_sync = Pay::Stripe.method(:sync_checkout_session)
    original_retrieve = Stripe::Checkout::Session.method(:retrieve)
    Pay::Stripe.define_singleton_method(:sync_checkout_session) { |session_id, **| synced << session_id }
    Stripe::Checkout::Session.define_singleton_method(:retrieve) do |*|
      Stripe::Checkout::Session.construct_from(id: "cs_test_theirs", customer: "cus_theirs")
    end

    get subscription_path(success: true, stripe_checkout_session_id: "cs_test_theirs")

    assert_empty synced
    assert_no_match "Thank you for subscribing", flash[:notice].to_s
  ensure
    Pay::Stripe.define_singleton_method(:sync_checkout_session, original_sync)
    Stripe::Checkout::Session.define_singleton_method(:retrieve, original_retrieve)
  end

  # @card-23.10
  test "a return whose session does not subscribe this household claims nothing" do
    FamilyPlates.config.mode = "hosted"
    original = Pay::Stripe.method(:sync_checkout_session)
    Pay::Stripe.define_singleton_method(:sync_checkout_session) { |*, **| nil }

    get subscription_path(success: true, stripe_checkout_session_id: "cs_test_someone_else")

    assert_response :success
    assert_no_match "Thank you for subscribing", flash[:notice].to_s
  ensure
    Pay::Stripe.define_singleton_method(:sync_checkout_session, original)
  end

  test "production does not grant a free subscription when Stripe is not configured" do
    FamilyPlates.config.mode = "hosted"
    household = @admin.household
    keys = %w[STRIPE_SECRET_KEY STRIPE_PRIVATE_KEY STRIPE_PUBLISHABLE_KEY STRIPE_PUBLIC_KEY]
    saved = keys.to_h { |name| [ name, ENV[name] ] }
    keys.each { |name| ENV.delete(name) }
    original_key = Pay::Stripe.method(:private_key)
    original_env = Rails.method(:env)
    Pay::Stripe.define_singleton_method(:private_key) { nil }
    Rails.define_singleton_method(:env) { ActiveSupport::EnvironmentInquirer.new("production") }

    assert_no_difference -> { Pay::Subscription.count } do
      post subscription_path, params: { plan: "monthly" }
    end

    assert_redirected_to subscription_path
    assert_equal "Billing is not available right now.", flash[:alert]
    assert_not household.reload.active_subscription?
  ensure
    Pay::Stripe.define_singleton_method(:private_key, original_key)
    Rails.define_singleton_method(:env, original_env)
    saved.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
  end

  # @card-23.4
  test "create in hosted mode subscribes to plan" do
    FamilyPlates.config.mode = "hosted"
    household = @admin.household

    post subscription_path, params: { plan: "annual" }
    assert_redirected_to subscription_path
    assert_equal "Successfully subscribed to the Annual plan! 🎉", flash[:notice]

    assert household.reload.active_subscription?
    assert_equal "annual", household.payment_processor.subscription.processor_plan
  end

  # @card-23.4
  test "create rejects non-admin users" do
    FamilyPlates.config.mode = "hosted"
    sign_in_user(@member_user)
    sign_in_as(@member)

    post subscription_path, params: { plan: "monthly" }
    assert_redirected_to root_path
    assert_equal "Access restricted to household organizers / admins.", flash[:alert]
  end

  # @card-23.5
  test "destroy in hosted mode cancels active subscription" do
    FamilyPlates.config.mode = "hosted"
    household = @admin.household

    post subscription_path, params: { plan: "monthly" }
    assert household.reload.active_subscription?

    delete subscription_path
    assert_redirected_to subscription_path
    assert_match(/Your subscription has been canceled/i, flash[:notice])

    sub = household.payment_processor.subscription
    assert sub.ends_at.present?
  end

  test "the billing portal sends a Stripe customer to their Stripe portal session" do
    FamilyPlates.config.mode = "hosted"
    household = @admin.household
    household.set_payment_processor :stripe, allow_fake: true, processor_id: "cus_portal"
    requested = []
    with_stripe_secret_key do
      stub_billing_portal(requested) do
        get portal_subscription_path
      end
    end

    assert_redirected_to "https://billing.stripe.com/p/session/test_portal"
    assert_equal [ [ "cus_portal", subscription_url ] ], requested
  end

  test "the billing portal falls back to the dashboard for a household Stripe has not seen" do
    FamilyPlates.config.mode = "hosted"
    requested = []
    with_stripe_secret_key do
      stub_billing_portal(requested) do
        get portal_subscription_path
      end
    end

    assert_redirected_to subscription_path
    assert_equal "Manage your subscription details below.", flash[:notice]
    assert_empty requested
  end

  test "the billing portal is for organizers only" do
    FamilyPlates.config.mode = "hosted"
    sign_in_user(@member_user)
    sign_in_as(@member)

    get portal_subscription_path

    assert_redirected_to root_path
    assert_equal "Access restricted to household organizers / admins.", flash[:alert]
  end

  test "the billing portal is not offered in appliance mode" do
    FamilyPlates.config.mode = "appliance"

    get portal_subscription_path

    assert_redirected_to root_path
  end

  test "Checkout applies the Stripe promotion an operator assigned to the household" do
    household = @admin.household
    PromotionProgram.create!(name: "Founders", code: "FOUNDERS", discount_percent: 50, provider_promotion_code_id: "promo_founders")
    household.update!(promotion_code: "FOUNDERS")

    args = checkout_with_real_stripe(household)

    assert_equal [ { promotion_code: "promo_founders" } ], args[:discounts]
    assert_equal({ metadata: { promotion_code: "FOUNDERS" } }, args[:subscription_data])
    assert_not args.key?(:allow_promotion_codes), "Stripe rejects discounts and allow_promotion_codes together"
  end

  test "Checkout lets a household with no assigned promotion type a code" do
    args = checkout_with_real_stripe(@admin.household)

    assert args[:allow_promotion_codes]
    assert_not args.key?(:discounts)
  end

  test "Checkout does not apply a promotion that has ended or Stripe does not know" do
    household = @admin.household
    PromotionProgram.create!(name: "Expired", code: "EXPIRED", provider_promotion_code_id: "promo_expired", ends_at: 1.day.ago)
    PromotionProgram.create!(name: "Local only", code: "LOCALONLY")

    %w[EXPIRED LOCALONLY].each do |code|
      household.update!(promotion_code: code)
      args = checkout_with_real_stripe(household)

      assert args[:allow_promotion_codes], code
      assert_not args.key?(:discounts), code
    end
  end

  private

  # Subscribes through the Stripe path, not the simulated one, and returns
  # what the app asked Stripe Checkout for.
  def checkout_with_real_stripe(household)
    FamilyPlates.config.mode = "hosted"
    household.set_payment_processor :stripe, allow_fake: true, processor_id: "cus_checkout"
    created = nil
    original = Stripe::Checkout::Session.method(:create)
    Stripe::Checkout::Session.define_singleton_method(:create) do |params, *|
      created = params
      Stripe::Checkout::Session.construct_from(url: "https://checkout.stripe.com/c/pay/cs_test_stub")
    end

    previous = ENV["ENABLE_REAL_STRIPE_TESTS"]
    ENV["ENABLE_REAL_STRIPE_TESTS"] = "true"
    with_stripe_secret_key { post subscription_path, params: { plan: "annual" } }

    assert_redirected_to "https://checkout.stripe.com/c/pay/cs_test_stub"
    created
  ensure
    previous ? ENV["ENABLE_REAL_STRIPE_TESTS"] = previous : ENV.delete("ENABLE_REAL_STRIPE_TESTS")
    Stripe::Checkout::Session.define_singleton_method(:create, original)
  end

  def with_stripe_secret_key
    previous = ENV["STRIPE_SECRET_KEY"]
    ENV["STRIPE_SECRET_KEY"] = "sk_test_portal"
    yield
  ensure
    previous ? ENV["STRIPE_SECRET_KEY"] = previous : ENV.delete("STRIPE_SECRET_KEY")
  end

  # Stands in for Stripe's billing portal API, recording who asked and where
  # Stripe should send them back.
  def stub_billing_portal(requested)
    original = Pay::Stripe::Customer.instance_method(:billing_portal)
    Pay::Stripe::Customer.define_method(:billing_portal) do |**options|
      requested << [ processor_id, options[:return_url] ]
      Stripe::BillingPortal::Session.construct_from(url: "https://billing.stripe.com/p/session/test_portal")
    end
    yield
  ensure
    Pay::Stripe::Customer.define_method(:billing_portal, original)
  end

  def sign_in_user(user)
    session_record = user.sessions.create!(token: SecureRandom.hex(32), kind: "browser")
    jar = ActionDispatch::Cookies::CookieJar.build(ActionDispatch::TestRequest.create, {})
    jar.signed[:session_token] = session_record.token
    cookies[:session_token] = jar[:session_token]
  end
end
