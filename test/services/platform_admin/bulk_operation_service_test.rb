# frozen_string_literal: true

require "test_helper"

module PlatformAdmin
  class BulkOperationServiceTest < ActiveSupport::TestCase
    setup do
      @operator = PlatformAdminAccount.create!(
        email: "operator@example.com",
        password: "correct horse battery staple",
        otp_secret: "JBSWY3DPEHPK3PXP"
      )
      @household1 = households(:one)
      @household2 = households(:two)

      @promo = PromotionProgram.create!(
        code: "BULKTEST20",
        name: "Bulk 20% Off",
        discount_percent: 20,
        active: true
      )
    end

    # @card-49.1
    test "preview calculates matched and eligible counts for tag operations" do
      @household1.add_operational_tag("beta_tester")
      @household1.save!

      service = BulkOperationService.new(
        operator: @operator,
        action: "add_tag",
        params: { tag: "beta_tester" },
        reason: "Testing cohort"
      )

      preview = service.preview
      assert_equal "add_tag", preview[:action]
      assert_operator preview[:matched_count], :>=, 2
      # household1 already has beta_tester, so it should be ineligible / skipped
      assert_operator preview[:ineligible_count], :>=, 1
    end

    # @card-49.6
    test "execute adds tag idempotently to matching households" do
      service = BulkOperationService.new(
        operator: @operator,
        action: "add_tag",
        params: { tag: "vip" },
        filter_params: { search: @household1.name },
        reason: "Promote key family"
      )

      assert_difference -> { PlatformAuditEvent.where(action: "bulk_operation.executed").count }, 1 do
        result = service.execute!
        assert_equal 1, result.success_count
        assert_equal 0, result.error_count
      end

      assert @household1.reload.has_operational_tag?("vip")

      # Re-executing is idempotent (skips already tagged)
      service2 = BulkOperationService.new(
        operator: @operator,
        action: "add_tag",
        params: { tag: "vip" },
        filter_params: { search: @household1.name },
        reason: "Repeat tag"
      )
      result2 = service2.execute!
      assert_equal 0, result2.success_count
      assert_equal 1, result2.skipped_count
    end

    # @card-49.6
    test "execute removes tag from matching households" do
      @household1.add_operational_tag("stale")
      @household1.save!

      service = BulkOperationService.new(
        operator: @operator,
        action: "remove_tag",
        params: { tag: "stale" },
        filter_params: { search: @household1.name },
        reason: "Cleanup stale tags"
      )

      result = service.execute!
      assert_equal 1, result.success_count
      assert_not @household1.reload.has_operational_tag?("stale")
    end

    # @card-49.8
    test "assign_promotion validates active promotion and applies to eligible households" do
      service = BulkOperationService.new(
        operator: @operator,
        action: "assign_promotion",
        params: { promotion_code: "BULKTEST20" },
        filter_params: { search: @household1.name },
        reason: "Onboarding promotion grant"
      )

      result = service.execute!
      assert_equal 1, result.success_count
      assert_equal "BULKTEST20", @household1.reload.promotion_code
    end

    # @card-49.7
    test "extend_trial extends trial date and rejects paid active subscriptions" do
      original_trial = @household1.trial_ends_at

      service = BulkOperationService.new(
        operator: @operator,
        action: "extend_trial",
        params: { days: 14 },
        filter_params: { search: @household1.name },
        reason: "Spring kitchen initiative"
      )

      result = service.execute!
      assert_equal 1, result.success_count
      assert @household1.reload.trial_extended_until.present?
      assert_operator @household1.trial_ends_at, :>, original_trial
    end

    # @card-49.9
    test "send_announcement creates support thread and operator message for households" do
      service = BulkOperationService.new(
        operator: @operator,
        action: "send_announcement",
        params: {
          subject: "Important System Maintenance",
          body: "We are updating the meal planner this Saturday."
        },
        filter_params: { search: @household1.name },
        reason: "Scheduled maintenance notice"
      )

      assert_difference -> { SupportThread.count }, 1 do
        assert_difference -> { SupportMessage.count }, 1 do
          result = service.execute!
          assert_equal 1, result.success_count
        end
      end

      thread = @household1.support_threads.order(:created_at).last
      assert_equal "Important System Maintenance", thread.subject
      assert_equal "waiting_on_customer", thread.status
      assert_equal @operator, thread.messages.first.platform_admin
    end

    # @card-49.2
    test "execute requires a non-blank reason" do
      service = BulkOperationService.new(
        operator: @operator,
        action: "add_tag",
        params: { tag: "test" },
        reason: "   "
      )

      assert_raises(ArgumentError) do
        service.execute!
      end
    end
  end
end
