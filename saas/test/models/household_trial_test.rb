# frozen_string_literal: true

require "test_helper"

# The free trial is one UTC instant: FREE_TRIAL_DAYS of elapsed time from
# creation, an operator's extension, or the moment verified paid service
# started. Active strictly before it. What the banner says follows from
# whether the household ever paid, has a payment pending, or neither.
class HouseholdTrialTest < ActiveSupport::TestCase
  include BillingConsentTestHelper

  setup do
    FamilyPlates.config.reset!
    FamilyPlates.config.mode = "hosted"
    @household = households(:one)
    @user = User.create!(email: "owner@trial.test")
    @household.update!(billing_owner: @user)
  end

  teardown { FamilyPlates.config.reset! }

  test "the trial ends exactly fourteen days of elapsed time after creation, active only before that instant" do
    created = Time.utc(2026, 9, 1, 15, 30, 0)
    @household.update_columns(created_at: created, trial_extended_until: nil)
    ends = Time.utc(2026, 9, 15, 15, 30, 0)
    assert_equal ends, @household.trial_ends_at

    travel_to(ends - 1.second) { assert @household.trial_active? }
    travel_to(ends) do
      assert_not @household.trial_active?
      assert_not @household.entitled?
      assert_equal 0, @household.trial_days_left
    end
  end

  test "a DST change in the household's zone does not move the end, and no local midnight is assumed" do
    @household.update_columns(time_zone: "America/New_York", trial_extended_until: nil,
      created_at: Time.utc(2026, 10, 25, 12, 0, 0)) # 8:00 AM EDT
    ends = @household.trial_ends_at
    assert_equal Time.utc(2026, 11, 8, 12, 0, 0), ends, "336 elapsed hours, across the November 1 change"
    assert_equal "2026-11-08 07:00:00 EST", ends.in_time_zone(@household.time_zone_object).strftime("%F %T %Z")

    @household.update_columns(time_zone: "Pacific/Auckland")
    assert_equal ends, @household.reload.trial_ends_at, "changing zone never moves the instant"
  end

  test "an extension is the end, to the second" do
    ext = Time.utc(2026, 12, 3, 17, 45, 12)
    @household.update_columns(trial_extended_until: ext)
    travel_to(ext - 1.second) { assert @household.trial_active? }
    travel_to(ext) { assert_not @household.trial_active? }
  end

  test "days left round up, and under a day says less than one day" do
    ends = Time.utc(2026, 9, 15, 12)
    @household.update_columns(trial_extended_until: ends)

    travel_to(ends - 13.days - 1.hour) { assert_equal 14, @household.trial_days_left }
    travel_to(ends - 1.day) do
      assert_equal 1, @household.trial_days_left
      assert_not @household.trial_less_than_one_day_left?
    end
    travel_to(ends - 1.day + 1.second) do
      assert_equal 1, @household.trial_days_left
      assert @household.trial_less_than_one_day_left?
    end
    travel_to(ends) { assert_not @household.trial_less_than_one_day_left? }
  end

  test "an unpaid household in its trial shows the trial banner, and after it ends the expired one" do
    ends = 3.days.from_now.change(usec: 0)
    @household.update_columns(trial_extended_until: ends)
    assert_equal :trial, @household.trial_banner_state
    travel_to(ends) { assert_equal :expired, @household.trial_banner_state }
  end

  test "an appliance never has a trial banner" do
    FamilyPlates.config.mode = "appliance"
    assert_nil @household.trial_banner_state
  end

  test "opening Checkout is not a payment: the trial banner stays" do
    @household.update_columns(trial_extended_until: 3.days.from_now)
    consent = BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
    consent.record_checkout_session!("cs_opened")
    assert_equal "open", consent.reload.checkout_state

    assert_not @household.subscription_payment_pending?
    assert_equal :trial, @household.trial_banner_state
  end

  test "a Checkout whose outcome is unknown, or an incomplete first payment, is pending and leaves the trial alone" do
    ends = 3.days.from_now.change(usec: 0)
    @household.update_columns(trial_extended_until: ends)
    consent = BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
    consent.update_columns(checkout_state: "unknown")
    assert_equal :pending, @household.trial_banner_state

    consent.update_columns(checkout_state: "expired")
    subscription = incomplete_subscription(consent)
    assert_equal :pending, @household.trial_banner_state
    assert_equal ends, @household.reload.trial_ends_at, "pending never ends the trial"

    subscription.update!(status: "incomplete_expired")
    assert_equal :trial, @household.reload.trial_banner_state, "a failed first payment returns to the plain trial"
    assert_nil consent.reload.confirmed_at
  end

  test "verified activation charges now: the remaining trial ends at that instant and the banner is gone" do
    @household.update_columns(trial_extended_until: 10.days.from_now)
    consent = BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
    subscription = incomplete_subscription(consent)
    assert_equal :pending, @household.trial_banner_state

    freeze_time do
      subscription.update!(status: "active")
      assert consent.reload.confirmed?
      assert_equal Time.current, @household.reload.trial_ends_at
      assert_not @household.trial_active?
      assert @household.entitled?, "paid service is what grants access now"
      assert_nil @household.trial_banner_state
    end
  end

  test "a replayed activation does not move the trial end again" do
    @household.update_columns(trial_extended_until: 10.days.from_now)
    consent = BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
    subscription = incomplete_subscription(consent)
    started = Time.current.change(usec: 0)
    travel_to(started) { subscription.update!(status: "active") }

    travel_to(started + 1.hour) { subscription.update!(current_period_end: 2.months.from_now) }
    assert_equal started, @household.reload.trial_ends_at
  end

  test "a payment confirmed after the trial ran out never lengthens it" do
    ended = 2.days.ago.change(usec: 0)
    @household.update_columns(trial_extended_until: ended)
    consent = BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
    incomplete_subscription(consent).update!(status: "active")

    assert consent.reload.confirmed?
    assert_equal ended, @household.reload.trial_ends_at
    assert @household.entitled?
  end

  test "an active subscription for a different price does not end the trial" do
    ends = 10.days.from_now.change(usec: 0)
    @household.update_columns(trial_extended_until: ends)
    consent = BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @user)
    consent.update_columns(stripe_price_id: "price_monthly_agreed")
    incomplete_subscription(consent, plan: "price_somebody_else").update!(status: "active")

    assert_nil consent.reload.confirmed_at
    assert_equal ends, @household.reload.trial_ends_at
  end

  test "a canceled paid subscription keeps access through its term, then lapses without the trial banner" do
    @household.update_columns(trial_extended_until: 1.day.ago)
    @household.set_payment_processor :fake_processor, allow_fake: true
    sub = @household.payment_processor.subscriptions.create!(
      name: "default", processor_id: "sub_cancel", processor_plan: "monthly", status: "active",
      current_period_start: 10.days.ago, current_period_end: 20.days.from_now, ends_at: 20.days.from_now
    )
    assert @household.entitled?
    assert_nil @household.trial_banner_state

    sub.update!(status: "canceled")
    travel_to(21.days.from_now) do
      assert_not @household.reload.entitled?
      assert_nil @household.trial_banner_state, "a household that paid is never told about a free trial again"
    end
  end

  test "the seven-day past-due renewal grace is unchanged" do
    @household.update_columns(trial_extended_until: 30.days.ago)
    @household.set_payment_processor :fake_processor, allow_fake: true
    period_end = 2.days.ago.change(usec: 0)
    @household.payment_processor.subscriptions.create!(
      name: "default", processor_id: "sub_past_due", processor_plan: "monthly", status: "past_due",
      current_period_start: period_end - 1.month, current_period_end: period_end
    )
    assert @household.entitled?
    assert_nil @household.trial_banner_state
    travel_to(period_end + 7.days - 1.second) { assert @household.reload.entitled? }
    travel_to(period_end + 7.days) { assert_not @household.reload.entitled? }
  end

  test "expiry deletes nothing" do
    @household.update_columns(trial_extended_until: 1.day.ago)
    assert_not @household.entitled?
    assert Household.exists?(@household.id)
    assert @household.family_members.exists?
  end

  private

  # The consent names no Stripe price in tests (no STRIPE_*_PRICE_ID), so any
  # plan matches it unless a test sets one.
  def incomplete_subscription(consent, plan: consent.stripe_price_id || "monthly")
    @household.set_payment_processor :fake_processor, allow_fake: true
    @household.payment_processor.subscriptions.create!(
      name: "default", processor_id: "sub_#{SecureRandom.hex(4)}", processor_plan: plan, status: "incomplete",
      current_period_start: Time.current, current_period_end: 1.month.from_now,
      metadata: { "billing_consent_id" => consent.id }
    )
  end
end
