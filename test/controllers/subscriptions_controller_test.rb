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
    synced = []
    original = Pay::Stripe.method(:sync_checkout_session)
    # Stands in for Stripe: what a completed Checkout leaves behind once synced.
    Pay::Stripe.define_singleton_method(:sync_checkout_session) do |session_id, **|
      synced << session_id
      household.set_payment_processor :fake_processor, allow_fake: true
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

  private

  def sign_in_user(user)
    session_record = user.sessions.create!(token: SecureRandom.hex(32), kind: "browser")
    jar = ActionDispatch::Cookies::CookieJar.build(ActionDispatch::TestRequest.create, {})
    jar.signed[:session_token] = session_record.token
    cookies[:session_token] = jar[:session_token]
  end
end
