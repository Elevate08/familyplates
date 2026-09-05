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

  test "show in appliance mode redirects to root" do
    FamilyPlates.config.mode = "appliance"
    get subscription_path
    assert_redirected_to root_path
    assert_equal "Subscriptions are only enabled in hosted mode.", flash[:notice]
  end

  test "show in hosted mode renders subscription dashboard" do
    FamilyPlates.config.mode = "hosted"
    get subscription_path
    assert_response :success
    assert_select "h1", text: /Subscription & Billing/i
    assert_select "button, input[type=submit]", text: /Subscribe/i
  end

  test "create in hosted mode subscribes to plan" do
    FamilyPlates.config.mode = "hosted"
    household = @admin.household

    post subscription_path, params: { plan: "annual" }
    assert_redirected_to subscription_path
    assert_equal "Successfully subscribed to the Annual plan! 🎉", flash[:notice]

    assert household.reload.active_subscription?
    assert_equal "annual", household.payment_processor.subscription.processor_plan
  end

  test "create rejects non-admin users" do
    FamilyPlates.config.mode = "hosted"
    sign_in_user(@member_user)
    sign_in_as(@member)

    post subscription_path, params: { plan: "monthly" }
    assert_redirected_to root_path
    assert_equal "Access restricted to household organizers / admins.", flash[:alert]
  end

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
