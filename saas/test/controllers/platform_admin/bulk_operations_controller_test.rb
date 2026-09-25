# frozen_string_literal: true

require "test_helper"

module PlatformAdmin
  class BulkOperationsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = PlatformAdminAccount.create!(
        email: "operator@example.com",
        password: "correct horse battery staple",
        otp_secret: "JBSWY3DPEHPK3PXP"
      )
      @household1 = households(:one)
      @household2 = households(:two)

      @promo = PromotionProgram.create!(
        code: "SUMMER50",
        name: "Summer 50% Off",
        discount_percent: 50,
        active: true
      )
    end

    # @card-49.5
    test "requires platform admin authentication for all actions" do
      get platform_admin_bulk_operations_url
      assert_redirected_to new_platform_admin_session_path

      get new_platform_admin_bulk_operation_url
      assert_redirected_to new_platform_admin_session_path

      post preview_platform_admin_bulk_operations_url
      assert_redirected_to new_platform_admin_session_path

      post platform_admin_bulk_operations_url
      assert_redirected_to new_platform_admin_session_path
    end

    test "index renders bulk operations history" do
      sign_in_as_operator(@admin)

      PlatformAuditEvent.record!(
        action: "bulk_operation.executed",
        actor: @admin,
        metadata: {
          bulk_action: "add_tag",
          reason: "Cohort testing",
          matched_count: 5,
          success_count: 5,
          skipped_count: 0
        }
      )

      get platform_admin_bulk_operations_url
      assert_response :success
      assert_includes response.body, "Guarded Bulk Operations"
      assert_includes response.body, "Cohort testing"
      assert_includes response.body, "5 updated"
    end

    test "new renders configuration form" do
      sign_in_as_operator(@admin)

      get new_platform_admin_bulk_operation_url
      assert_response :success
      assert_includes response.body, "Configure Bulk Operation"
      assert_includes response.body, "Add Operational Tag"
      assert_includes response.body, "Assign Approved Promotion"
      assert_includes response.body, "Extend Free Trial"
      assert_includes response.body, "Send Service Announcement"
    end

    # @card-49.1
    test "preview validates reason and renders preview statistics and sample households" do
      sign_in_as_operator(@admin)

      post preview_platform_admin_bulk_operations_url, params: {
        bulk_action: "add_tag",
        operation_params: { tag: "beta" },
        reason: "Spring feature rollout",
        filter_params: { search: @household1.name }
      }

      assert_response :success
      assert_includes response.body, "Preview Bulk Operation"
      assert_includes response.body, "Eligible to Update"
      assert_includes response.body, "Spring feature rollout"
      assert_includes response.body, @household1.name
    end

    # @card-49.2
    test "preview rejects empty reason" do
      sign_in_as_operator(@admin)

      post preview_platform_admin_bulk_operations_url, params: {
        bulk_action: "add_tag",
        operation_params: { tag: "beta" },
        reason: ""
      }

      assert_response :unprocessable_entity
      assert_includes response.body, "valid operational reason is required"
    end

    # @card-49.3
    test "create rejects execution when unconfirmed" do
      sign_in_as_operator(@admin)

      post platform_admin_bulk_operations_url, params: {
        bulk_action: "add_tag",
        operation_params: { tag: "beta" },
        reason: "Spring rollout",
        confirmed: "0"
      }

      assert_redirected_to new_platform_admin_bulk_operation_path
      follow_redirect!
      assert_includes response.body, "Bulk operation was not confirmed"
    end

    # @card-42.3 @card-49.7
    test "support operators cannot extend trials or assign promotions in bulk" do
      support = PlatformAdminAccount.create!(
        email: "support@example.com", password: "correct horse battery staple", role: "support"
      )
      sign_in_as_operator(support)
      before = @household1.trial_ends_at

      post platform_admin_bulk_operations_url, params: {
        bulk_action: "extend_trial",
        operation_params: { days: "30" },
        filter_params: { search: @household1.name },
        reason: "Goodwill",
        confirmed: "1"
      }

      assert_redirected_to new_platform_admin_bulk_operation_path
      assert_equal "Operation aborted: Only owner and billing operators can change a household's billing.", flash[:alert]
      assert_equal before.to_i, @household1.reload.trial_ends_at.to_i
      assert_nil @household1.promotion_code

      post platform_admin_bulk_operations_url, params: {
        bulk_action: "assign_promotion",
        operation_params: { promotion_code: "SUMMER50" },
        filter_params: { search: @household1.name },
        reason: "Goodwill",
        confirmed: "1"
      }

      assert_nil @household1.reload.promotion_code
    end

    # @card-49.7
    test "a bulk trial extension longer than 90 days is refused" do
      sign_in_as_operator(@admin)
      before = @household1.trial_ends_at

      post platform_admin_bulk_operations_url, params: {
        bulk_action: "extend_trial",
        operation_params: { days: "36500" },
        filter_params: { search: @household1.name },
        reason: "Forever",
        confirmed: "1"
      }

      assert_redirected_to new_platform_admin_bulk_operation_path
      assert_match "1 to 90 days", flash[:alert]
      assert_equal before.to_i, @household1.reload.trial_ends_at.to_i
    end

    # @card-49.4
    test "create executes bulk operation and records audit log" do
      sign_in_as_operator(@admin)

      assert_difference -> { PlatformAuditEvent.where(action: "bulk_operation.executed").count }, 1 do
        post platform_admin_bulk_operations_url, params: {
          bulk_action: "add_tag",
          operation_params: { tag: "verified" },
          filter_params: { search: @household1.name },
          reason: "Manual operator tagging",
          confirmed: "1"
        }
      end

      assert_redirected_to platform_admin_bulk_operations_path
      follow_redirect!
      assert_includes response.body, "Bulk operation executed successfully"
      assert @household1.reload.has_operational_tag?("verified")
    end

    private

    def sign_in_as_operator(admin)
      post platform_admin_session_path, params: {
        email: admin.email,
        password: "correct horse battery staple",
        otp_code: PlatformAdminAccount::Totp.code(admin.otp_secret)
      }
      assert_response :redirect
    end
  end
end
