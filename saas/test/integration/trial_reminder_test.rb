# frozen_string_literal: true

require "test_helper"

class TrialReminderTest < ActiveSupport::TestCase
  include BillingConsentTestHelper

  ENDS = Time.utc(2026, 11, 8, 12, 0, 0)

  setup do
    FamilyPlates.config.reset!
    FamilyPlates.config.mode = "hosted"
    ActionMailer::Base.deliveries.clear
    @owner = User.create!(email: "owner@reminder.test", **accepted_terms)
    @household = households(:one)
    @household.update_columns(billing_owner_user_id: @owner.id, trial_extended_until: ENDS, time_zone: "America/New_York")
  end

  teardown { FamilyPlates.config.reset! }

  test "the owner is told 72 hours ahead, once, with the exact end and no offer" do
    run_at(ENDS - 72.hours - 1.second)
    assert_empty ActionMailer::Base.deliveries, "not before it is due"

    run_at(ENDS - 72.hours)
    run_at(ENDS - 72.hours + 59.minutes)
    assert_equal 1, ActionMailer::Base.deliveries.size

    mail = ActionMailer::Base.deliveries.last
    assert_equal [ "owner@reminder.test" ], mail.to
    assert_equal "Your FamilyPlates free trial ends November 8", mail.subject
    text = mail.text_part.body.to_s
    assert_includes text, "November 8, 2026 at 7:00 AM EST"
    assert_includes text, "nothing is charged automatically"
    assert_includes text, "/subscription"
    assert_no_match(/\$|month|year/i, text, "an account notice, not an offer")
    assert_includes mail.html_part.body.to_s, %(<time datetime="2026-11-08T12:00:00Z">)
  end

  test "the 24-hour reminder follows, and each is recorded once" do
    run_at(ENDS - 72.hours)
    run_at(ENDS - 24.hours)
    run_at(ENDS - 24.hours + 30.minutes)

    assert_equal 2, ActionMailer::Base.deliveries.size
    assert_equal %w[24_hours 72_hours], NoticeDelivery.where(household_id: @household.id).order(:threshold).pluck(:threshold)
    assert NoticeDelivery.where(household_id: @household.id).all?(&:sent_at)
  end

  test "a missed hour does not send a stale reminder later" do
    run_at(ENDS - 72.hours + 1.hour)
    assert_empty ActionMailer::Base.deliveries
  end

  test "a trial that only runs from creation is reminded too" do
    @household.update_columns(trial_extended_until: nil, created_at: ENDS - Household::Billing::FREE_TRIAL_DAYS.days)
    run_at(ENDS - 72.hours + 5.minutes)
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  test "an extended trial is reminded about its new end, not the old one" do
    run_at(ENDS - 72.hours)
    later = ENDS + 7.days
    @household.update_columns(trial_extended_until: later)

    run_at(ENDS - 24.hours)
    assert_equal 1, ActionMailer::Base.deliveries.size, "the old end is no longer due"

    run_at(later - 72.hours)
    assert_equal 2, ActionMailer::Base.deliveries.size
    assert_includes ActionMailer::Base.deliveries.last.text_part.body.to_s, "November 15, 2026"
  end

  test "no reminder for a household that paid, is paying, is suspended, is being deleted or has no owner" do
    cases = {
      "paid" => -> {
        @household.set_payment_processor :fake_processor, allow_fake: true
        @household.payment_processor.subscriptions.create!(name: "default", processor_id: "sub_paid", processor_plan: "monthly", status: "active")
      },
      "pending payment" => -> {
        BillingConsent.reserve(BillingOffer.for(:monthly), household: @household, user: @owner).update_columns(checkout_state: "unknown")
      },
      "suspended" => -> { @household.update_columns(suspended_at: Time.current) },
      "deletion requested" => -> { @household.account_deletion_requests.create!(requested_at: Time.current) },
      "no owner" => -> { @household.update_columns(billing_owner_user_id: nil) }
    }

    cases.each do |name, arrange|
      ActiveRecord::Base.transaction do
        arrange.call
        run_at(ENDS - 72.hours)
        assert_empty ActionMailer::Base.deliveries, name
        raise ActiveRecord::Rollback
      end
    end
  end

  test "an appliance sends nothing" do
    FamilyPlates.config.mode = "appliance"
    run_at(ENDS - 72.hours)
    assert_empty ActionMailer::Base.deliveries
  end

  test "a failed send releases the reminder so the next run in the hour retries it" do
    begin
      TrialReminderMailer.define_singleton_method(:trial_ending) { |*| raise Net::SMTPServerBusy, "synthetic" }
      run_at(ENDS - 72.hours)
    ensure
      TrialReminderMailer.singleton_class.remove_method(:trial_ending)
    end
    assert_empty ActionMailer::Base.deliveries
    assert_not NoticeDelivery.exists?(household_id: @household.id)

    run_at(ENDS - 72.hours + 30.minutes)
    assert_equal 1, ActionMailer::Base.deliveries.size
  end

  private

  def run_at(time)
    travel_to(time) { TrialReminderJob.perform_now(now: time) }
  end
end
