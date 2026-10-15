# frozen_string_literal: true

require "test_helper"

# The trial banner on household pages, and what a household keeps once its
# trial or paid term has ended: no kitchen, read or write, by any route; but
# signing in and out, profiles, the subscription page, legal documents,
# support, devices and the owner's export and deletion request all stay open,
# without redirect loops, and nothing is deleted.
class TrialBannerAndExpiryAccessTest < ActionDispatch::IntegrationTest
  include BillingConsentTestHelper

  setup do
    FamilyPlates.config.reset!
    FamilyPlates.config.mode = "hosted"
    @household = households(:one)
    @owner = User.create!(email: "owner@banner.test", **accepted_terms)
    @admin = family_members(:one)
    @admin.update!(user: @owner)
    @household.update!(billing_owner: @owner)
    @member_user = User.create!(email: "member@banner.test", **accepted_terms)
    @member = family_members(:two)
    @member.update!(user: @member_user)
  end

  teardown { FamilyPlates.config.reset! }

  # --- The banner ------------------------------------------------------------

  test "the billing owner sees the exact trial status with the end in the household's zone and a Subscribe link" do
    ends = Time.utc(2026, 11, 8, 12, 0, 0)
    @household.update_columns(trial_extended_until: ends, time_zone: "America/New_York")
    travel_to(Time.utc(2026, 11, 3, 9, 0, 0)) do
      sign_in_owner
      get recipes_path
      assert_response :success

      assert_select "section[aria-label='Free trial status'][data-trial-banner-state=trial]" do
        assert_select "time[datetime='2026-11-08T12:00:00Z']", text: "November 8, 2026 at 7:00 AM EST"
        assert_select "a[href=?]", subscription_path, text: "Subscribe"
      end
      assert_equal "6 days left Your free trial ends November 8, 2026 at 7:00 AM EST. " \
        "Subscribe to keep using your household. Payment not setup.", banner_paragraph_text
    end
  end

  test "a household with no zone is shown its end in UTC" do
    @household.update_columns(trial_extended_until: Time.utc(2026, 11, 8, 12, 0, 0), time_zone: nil)
    travel_to(Time.utc(2026, 11, 7, 18, 0, 0)) do
      sign_in_owner
      get recipes_path
      assert_select "[data-testid=trial-banner] time", text: "November 8, 2026 at 12:00 PM UTC"
      assert_select "[data-testid=trial-banner]", text: /Less than 1 day left/
    end
  end

  test "someone who does not own billing is asked to go to the owner, with no billing control" do
    @household.update_columns(trial_extended_until: 5.days.from_now)
    sign_in_user(@member_user)
    sign_in_as(@member)
    get recipes_path

    assert_select "[data-testid=trial-banner]", text: /Ask your household owner to subscribe to keep using your household\.\s+Payment not setup\./
    assert_select "[data-testid=trial-banner] a", count: 0
  end

  test "the owner on a kitchen display, or on another profile, is not offered Subscribe" do
    @household.update_columns(trial_extended_until: 5.days.from_now)
    sign_in_user(@owner).update!(kind: "kiosk")
    sign_in_as(@admin)
    get recipes_path
    assert_select "[data-testid=trial-banner] a", count: 0

    sign_in_user(@owner)
    @member.update!(user: nil)
    sign_in_as(@member)
    get recipes_path
    assert_select "[data-testid=trial-banner] a", count: 0
  end

  test "the subscription page shows the status without linking to itself" do
    @household.update_columns(trial_extended_until: 5.days.from_now)
    sign_in_owner
    get subscription_path
    assert_response :success
    assert_select "[data-testid=trial-banner]", text: /Payment not setup\./
    assert_select "[data-testid=trial-banner] a", count: 0
  end

  test "a payment awaiting confirmation shows a pending status, not Payment not setup, and keeps the trial end" do
    ends = 5.days.from_now.change(usec: 0)
    @household.update_columns(trial_extended_until: ends)
    consent = BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @owner)
    consent.update_columns(checkout_state: "unknown")

    sign_in_owner
    get recipes_path
    assert_response :success
    assert_select "section[aria-label='Subscription payment status'][data-trial-banner-state=pending]",
      text: /Payment pending\.\s+We are confirming whether your subscription payment went through\.\s+Your free trial still ends/
    assert_no_match "Payment not setup", response.body
    assert_equal ends, @household.reload.trial_ends_at
  end

  test "after paying the banner is gone for everyone" do
    @household.update_columns(trial_extended_until: 5.days.from_now)
    sign_in_owner
    post subscription_path, params: consent_params(:monthly, household: @household, user: @owner)
    assert @household.reload.active_subscription?

    get recipes_path
    assert_response :success
    assert_select "[data-testid=trial-banner]", count: 0
    assert_no_match "Payment not setup", response.body
  end

  test "signed-out pages and an appliance have no banner" do
    @household.update_columns(trial_extended_until: 5.days.from_now)
    get new_session_path
    assert_select "[data-testid=trial-banner]", count: 0

    FamilyPlates.config.mode = "appliance"
    sign_in_as(@admin)
    get recipes_path
    assert_response :success
    assert_select "[data-testid=trial-banner]", count: 0
  end

  # --- After expiry: no kitchen ---------------------------------------------

  test "at the exact end instant kitchen pages go to the subscription page, owner and member alike" do
    ends = 2.days.from_now.change(usec: 0)
    @household.update_columns(trial_extended_until: ends)
    sign_in_owner

    travel_to(ends - 1.second) do
      get recipes_path
      assert_response :success
    end

    travel_to(ends) do
      get recipes_path
      assert_redirected_to subscription_path
      assert_response :see_other
      assert_equal HostedAccess::TRIAL_ENDED_OWNER_ALERT, flash[:alert]

      sign_in_user(@member_user)
      sign_in_as(@member)
      get meal_plans_path
      assert_redirected_to subscription_path
      assert_equal HostedAccess::TRIAL_ENDED_MEMBER_ALERT, flash[:alert]
      follow_redirect!
      assert_response :success, "the subscription page is never itself gated: no loop"
      assert_select "[data-trial-banner-state=expired]", text: /Your free trial ended/
    end
  end

  test "an expired household cannot write by form, Turbo or JSON, and reads nothing as JSON" do
    expire!
    sign_in_owner

    assert_no_difference -> { @household.recipes.count } do
      post recipes_path, params: { recipe: { title: "Sneaky" } }
      assert_redirected_to subscription_path

      post recipes_path, params: { recipe: { title: "Sneaky" } }, as: :turbo_stream
      assert_redirected_to subscription_path
    end

    get recipes_path, as: :json
    assert_response :forbidden
    assert_equal "subscription_required", response.parsed_body["error"]
    assert_equal subscription_path, response.parsed_body["redirect_url"]
    assert_no_match(/Spencer|recipe/i, response.parsed_body.except("error", "message", "redirect_url").to_s)
  end

  test "the home page sends an expired household to the subscription page without creating a meal plan" do
    expire!
    sign_in_owner

    assert_no_difference -> { MealPlan.where(household: @household).count } do
      get root_path
    end
    assert_redirected_to subscription_path
  end

  test "the calendar feed stops at expiry and resumes on subscribing; other tenants are unaffected" do
    @household.update_columns(trial_extended_until: 5.days.from_now)
    get calendar_feed_url(token: @household.calendar_feed_token, format: :ics)
    assert_response :success

    expire!
    get calendar_feed_url(token: @household.calendar_feed_token, format: :ics)
    assert_response :forbidden
    assert_not_includes response.body, "BEGIN:VCALENDAR"
    get calendar_member_feed_url(token: @household.calendar_feed_token, member_id: @admin.id, format: :ics)
    assert_response :forbidden

    other = households(:two)
    other.update_columns(trial_extended_until: 5.days.from_now)
    get calendar_feed_url(token: other.calendar_feed_token, format: :ics)
    assert_response :success

    sign_in_owner
    post subscription_path, params: consent_params(:monthly, household: @household, user: @owner)
    get calendar_feed_url(token: @household.calendar_feed_token, format: :ics)
    assert_response :success, "the same link works again once paid"
  end

  test "a pending payment after expiry says so, and still opens nothing" do
    expire!
    consent = BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @owner)
    consent.update_columns(checkout_state: "unknown")
    sign_in_owner

    get recipes_path
    assert_redirected_to subscription_path
    assert_equal HostedAccess::PAYMENT_PENDING_ALERT, flash[:alert]
  end

  test "a household whose paid term ended is told its subscription is not active, not that a trial ended" do
    expire!
    @household.set_payment_processor :fake_processor, allow_fake: true
    @household.payment_processor.subscriptions.create!(
      name: "default", processor_id: "sub_lapsed", processor_plan: "monthly", status: "canceled",
      current_period_start: 2.months.ago, current_period_end: 1.month.ago, ends_at: 1.month.ago
    )
    sign_in_owner
    get recipes_path
    assert_redirected_to subscription_path
    assert_equal HostedAccess::SUBSCRIPTION_INACTIVE_OWNER_ALERT, flash[:alert]
    follow_redirect!
    assert_select "[data-testid=trial-banner]", count: 0
  end

  test "a lapsed paid household whose new subscription payment is pending is told so, not asked to renew" do
    expire!
    @household.set_payment_processor :fake_processor, allow_fake: true
    @household.payment_processor.subscriptions.create!(
      name: "default", processor_id: "sub_lapsed", processor_plan: "monthly", status: "canceled",
      current_period_start: 2.months.ago, current_period_end: 1.month.ago, ends_at: 1.month.ago
    )
    @household.payment_processor.subscriptions.create!(
      name: "default", processor_id: "sub_renewing", processor_plan: "monthly", status: "incomplete",
      current_period_start: Time.current, current_period_end: 1.month.from_now
    )
    sign_in_owner
    get recipes_path
    assert_redirected_to subscription_path
    assert_equal HostedAccess::PAYMENT_PENDING_ALERT, flash[:alert]
  end

  # --- After expiry: what stays open ----------------------------------------

  test "service, legal, support, account and sign-out paths stay open after expiry" do
    expire!
    sign_in_owner

    [ subscription_path, select_profile_path, terms_path, privacy_path, support_threads_path,
      account_data_path, devices_path ].each do |path|
      get path
      assert_response :success, path
    end

    get export_account_data_path
    assert_response :success
    assert_equal "application/json", response.media_type

    assert_difference -> { @household.account_deletion_requests.count }, 1 do
      post request_deletion_account_data_path
    end
    assert_redirected_to account_data_path

    delete session_path
    assert cookies[:session_token].blank?
    assert Household.exists?(@household.id), "expiry and sign-out delete nothing"
  end

  test "export and deletion requests stay the organizer's alone after expiry" do
    expire!
    sign_in_user(@member_user)
    sign_in_as(@member)

    get export_account_data_path
    assert_redirected_to root_path
    assert_no_difference -> { AccountDeletionRequest.count } do
      post request_deletion_account_data_path
    end
  end

  test "someone who must accept changed Terms in an expired household reaches the subscription page, not a loop" do
    expire!
    @owner.update_columns(terms_version: nil, terms_accepted_at: nil)
    sign_in_owner

    get recipes_path
    assert_redirected_to subscription_path
    follow_redirect!
    assert_response :success

    get terms_acceptance_path
    assert_response :success
    get terms_path
    assert_response :success
  end

  test "one household's expiry does not touch another's" do
    expire!
    other = households(:two)
    other.update_columns(trial_extended_until: 5.days.from_now)
    other_user = User.create!(email: "other@banner.test", **accepted_terms)
    other_admin = other.family_members.create!(name: "Other", role: "admin", pin: "1234", user: other_user,
      avatar_color: "#3B82F6", avatar_icon: "star")
    other.update!(billing_owner: other_user)

    sign_in_user(other_user)
    sign_in_as(other_admin)
    get recipes_path
    assert_response :success
    assert_select "[data-trial-banner-state=trial]"
  end

  test "an appliance never gates, whatever the dates say" do
    expire!
    FamilyPlates.config.mode = "appliance"
    sign_in_as(@admin)
    get recipes_path
    assert_response :success
    get calendar_feed_url(token: @household.calendar_feed_token, format: :ics)
    assert_response :success
  end

  private

  def expire!
    @household.update_columns(trial_extended_until: 1.minute.ago)
  end

  def sign_in_owner
    sign_in_user(@owner)
    sign_in_as(@admin)
  end

  def banner_paragraph_text
    css_select("[data-testid=trial-banner] p").first.text.squish
  end
end
