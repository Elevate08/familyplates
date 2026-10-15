# frozen_string_literal: true

require "test_helper"

module PlatformAdmin
  class BillingOwnerRecoveryTest < ActiveSupport::TestCase
    EVIDENCE = "Support thread: confirmed the last four of the card and the signup date"

    setup do
      @operator = PlatformAdminAccount.create!(
        email: "operator@example.com", password: "correct horse battery staple", role: "billing"
      )
      @household = households(:one)
      @previous_owner = User.create!(email: "former@household.test", terms_accepted_at: 1.year.ago, terms_version: "2026-01-01")
      @household.update!(billing_owner: @previous_owner)
      @organizer_user = User.create!(email: "organizer@household.test")
      family_members(:one).update!(user: @organizer_user)
      @member_user = User.create!(email: "member@household.test")
      family_members(:two).update!(user: @member_user)
    end

    test "an operator with identity evidence makes the household's own organizer the billing owner" do
      recovery.assign!(user: @organizer_user, identity_evidence: EVIDENCE)

      assert_equal @organizer_user, @household.reload.billing_owner
      event = PlatformAuditEvent.find_by!(action: "household.billing_owner_recovered", target_id: @household.id)
      assert_equal @operator, event.platform_admin
      assert_equal @organizer_user.id, event.metadata["user_id"]
      assert_equal @previous_owner.id, event.metadata["previous_owner_user_id"]
      assert_equal EVIDENCE, event.metadata["identity_evidence"]
    end

    test "recovery restores an owner to a household that has none" do
      @household.update!(billing_owner: nil)

      recovery.assign!(user: @organizer_user, identity_evidence: EVIDENCE)

      assert_equal @organizer_user, @household.reload.billing_owner
    end

    test "recovery moves no subscription, card or consent to the new owner" do
      @household.set_payment_processor :fake_processor, allow_fake: true
      customer = @household.payment_processor
      subscription = customer.subscriptions.create!(
        name: "default", processor_id: "sub_kept", processor_plan: "monthly", status: "active",
        current_period_start: Time.current, current_period_end: 1.month.from_now
      )
      card = customer.payment_methods.create!(processor_id: "pm_kept", payment_method_type: "card", default: true)

      assert_no_difference [ -> { Pay::Customer.count }, -> { Pay::Subscription.count }, -> { Pay::PaymentMethod.count } ] do
        recovery.assign!(user: @organizer_user, identity_evidence: EVIDENCE)
      end

      assert_equal [ customer ], @household.reload.pay_customers.to_a
      assert_equal customer, @household.payment_processor
      assert_equal [ "sub_kept", "active", nil ], subscription.reload.values_at(:processor_id, :status, :ends_at)
      assert_equal [ customer.id, true ], card.reload.values_at(:customer_id, :default)
      assert_nil @organizer_user.reload.terms_accepted_at
      assert_nil @organizer_user.terms_version
      assert_equal "2026-01-01", @previous_owner.reload.terms_version
    end

    test "missing or thin identity evidence changes nothing" do
      [ nil, "", "verified", " " * 30 ].each do |evidence|
        assert_raises(BillingOwnerRecovery::Error, evidence.inspect) do
          recovery.assign!(user: @organizer_user, identity_evidence: evidence)
        end
      end

      assert_equal @previous_owner, @household.reload.billing_owner
      assert_not PlatformAuditEvent.exists?(action: "household.billing_owner_recovered")
    end

    test "only a user holding their own admin profile in the household can be made owner" do
      outsider = User.create!(email: "outsider@example.com")
      households(:two).family_members.create!(name: "Miller", role: "admin", user: outsider, pin: "1234")

      [ @member_user, outsider, nil ].each do |user|
        assert_raises(BillingOwnerRecovery::Error, user&.email.inspect) do
          recovery.assign!(user: user, identity_evidence: EVIDENCE)
        end
      end

      assert_equal @previous_owner, @household.reload.billing_owner
    end

    test "an operator without billing rights cannot recover ownership" do
      support = PlatformAdminAccount.create!(email: "support@example.com", password: "correct horse battery staple", role: "support")

      [ support, nil ].each do |operator|
        assert_raises(BillingOwnerRecovery::Error) do
          BillingOwnerRecovery.new(@household, operator: operator).assign!(user: @organizer_user, identity_evidence: EVIDENCE)
        end
      end

      assert_equal @previous_owner, @household.reload.billing_owner
    end

    test "naming the current owner again is refused" do
      @household.update!(billing_owner: @organizer_user)

      assert_raises(BillingOwnerRecovery::Error) do
        recovery.assign!(user: @organizer_user, identity_evidence: EVIDENCE)
      end
      assert_not PlatformAuditEvent.exists?(action: "household.billing_owner_recovered")
    end

    private

    def recovery
      BillingOwnerRecovery.new(@household, operator: @operator)
    end
  end
end
