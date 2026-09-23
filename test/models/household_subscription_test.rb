# frozen_string_literal: true

require "test_helper"

class HouseholdSubscriptionTest < ActiveSupport::TestCase
  setup do
    FamilyPlates.config.reset!
    @household = households(:one)
  end

  teardown do
    FamilyPlates.config.reset!
  end

  test "appliance mode is always entitled regardless of subscription or trial state" do
    FamilyPlates.config.mode = "appliance"
    @household.update_columns(created_at: 100.days.ago)

    assert @household.entitled?
    assert_equal :appliance, @household.subscription_status
  end

  test "hosted mode fresh household is entitled via free trial" do
    FamilyPlates.config.mode = "hosted"
    @household.update_columns(created_at: 2.days.ago)

    assert @household.trial_active?
    assert_equal 12, @household.trial_days_left
    assert @household.entitled?
    assert_equal :trialing, @household.subscription_status
  end

  test "hosted mode expired trial without subscription is not entitled" do
    FamilyPlates.config.mode = "hosted"
    @household.update_columns(created_at: 20.days.ago)

    assert_not @household.trial_active?
    assert_equal 0, @household.trial_days_left
    assert_not @household.entitled?
    assert_equal :expired, @household.subscription_status
  end

  test "hosted mode active subscription grants entitlement" do
    FamilyPlates.config.mode = "hosted"
    @household.update_columns(created_at: 30.days.ago)

    @household.set_payment_processor :fake_processor, allow_fake: true
    sub = @household.payment_processor.subscriptions.create!(
      name: "default",
      processor_id: "sub_123",
      processor_plan: "monthly",
      status: "active",
      current_period_start: Time.current,
      current_period_end: 1.month.from_now
    )

    assert @household.active_subscription?
    assert @household.entitled?
    assert_equal :active, @household.subscription_status
  end

  test "hosted mode canceled subscription remains entitled until period ends" do
    FamilyPlates.config.mode = "hosted"
    @household.update_columns(created_at: 30.days.ago)

    @household.set_payment_processor :fake_processor, allow_fake: true
    sub = @household.payment_processor.subscriptions.create!(
      name: "default",
      processor_id: "sub_123",
      processor_plan: "monthly",
      status: "active",
      current_period_start: 15.days.ago,
      current_period_end: 15.days.from_now,
      ends_at: 15.days.from_now
    )

    assert @household.active_subscription?
    assert @household.entitled?

    # Fast forward after period end
    sub.update_columns(ends_at: 1.day.ago, status: "canceled")
    assert_not @household.active_subscription?
    assert_not @household.entitled?
    assert_equal :canceled, @household.subscription_status
  end

  test "hosted mode past_due subscription has 7-day grace period" do
    FamilyPlates.config.mode = "hosted"
    @household.update_columns(created_at: 30.days.ago)

    @household.set_payment_processor :fake_processor, allow_fake: true
    sub = @household.payment_processor.subscriptions.create!(
      name: "default",
      processor_id: "sub_123",
      processor_plan: "monthly",
      status: "past_due",
      current_period_start: 1.month.ago,
      current_period_end: 2.days.ago,
      updated_at: 2.days.ago
    )

    assert @household.past_due_grace_active?
    assert @household.entitled?
    assert_equal :past_due_grace, @household.subscription_status

    # After 7-day grace window
    sub.update_columns(current_period_end: 10.days.ago, updated_at: 10.days.ago)
    assert_not @household.past_due_grace_active?
    assert_not @household.entitled?
    assert_equal :past_due, @household.subscription_status
  end

  test "each remaining Stripe subscription status is named and does not grant access" do
    FamilyPlates.config.mode = "hosted"
    @household.update_columns(created_at: 30.days.ago)
    @household.set_payment_processor :fake_processor, allow_fake: true

    expectations = {
      "trialing" => [ :trialing, true ],
      "incomplete" => [ :incomplete, false ],
      "incomplete_expired" => [ :incomplete_expired, false ],
      "unpaid" => [ :unpaid, false ],
      "paused" => [ :paused, false ]
    }

    expectations.each do |stripe_status, (label, entitled)|
      @household.payment_processor.subscriptions.delete_all
      @household.payment_processor.subscriptions.create!(
        name: "default",
        processor_id: "sub_#{stripe_status}",
        processor_plan: "monthly",
        status: stripe_status,
        current_period_start: Time.current,
        current_period_end: 1.month.from_now,
        trial_ends_at: (stripe_status == "trialing" ? 10.days.from_now : nil)
      )
      @household.reload

      assert_equal label, @household.subscription_status, stripe_status
      assert_equal entitled, @household.entitled?, stripe_status
    end
  end
end
