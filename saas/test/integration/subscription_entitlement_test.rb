# frozen_string_literal: true

require "test_helper"

class SubscriptionEntitlementTest < ActionDispatch::IntegrationTest
  include BillingConsentTestHelper

  setup do
    FamilyPlates.config.reset!
    @household = households(:one)
    @user = User.create!(email: "admin_organizer@household.test", **accepted_terms)
    @admin = family_members(:one)
    @admin.update!(user: @user)
    @household.update!(billing_owner: @user)

    @member_user = User.create!(email: "kid@household.test", **accepted_terms)
    @member = family_members(:two)
    @member.update!(user: @member_user)
  end

  teardown do
    FamilyPlates.config.reset!
  end

  # @card-23.2
  test "hosted mode gates unentitled households and restores access upon subscribing" do
    FamilyPlates.config.mode = "hosted"
    # Expire trial
    @household.update_columns(created_at: 25.days.ago)

    # 1. Admin accessing meal plans is redirected to subscription page
    sign_in_user(@user)
    sign_in_as(@admin)

    get recipes_path
    assert_redirected_to subscription_path
    assert_equal HostedAccess::TRIAL_ENDED_OWNER_ALERT, flash[:alert]

    # 2. A member without billing authority goes to the same page, which has
    # no Subscribe control for them, and is asked to go to the owner.
    sign_in_user(@member_user)
    sign_in_as(@member)

    get recipes_path
    assert_redirected_to subscription_path
    assert_equal HostedAccess::TRIAL_ENDED_MEMBER_ALERT, flash[:alert]

    # 3. Admin visits subscription page and subscribes
    sign_in_user(@user)
    sign_in_as(@admin)

    get subscription_path
    assert_response :success

    post subscription_path, params: consent_params(:monthly, household: @household, user: @user)
    assert_redirected_to subscription_path
    assert @household.reload.active_subscription?

    # 4. Meal planning and recipe access are immediately restored for admin
    get recipes_path
    assert_response :success

    # 5. Meal planning access is restored for non-admin member as well
    sign_in_user(@member_user)
    sign_in_as(@member)

    get recipes_path
    assert_response :success
  end

  # @card-23.3
  test "appliance mode never blocks access even without subscription or active trial" do
    FamilyPlates.config.mode = "appliance"
    assert @household.entitled?

    sign_in_as(@admin)
    get recipes_path
    assert_response :success
  end

  private

  def sign_in_user(user)
    session_record = user.sessions.create!(token: SecureRandom.hex(32), kind: "browser")
    jar = ActionDispatch::Cookies::CookieJar.build(ActionDispatch::TestRequest.create, {})
    jar.signed[:session_token] = session_record.token
    cookies[:session_token] = jar[:session_token]
  end
end
