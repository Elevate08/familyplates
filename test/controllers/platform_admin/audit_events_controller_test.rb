require "test_helper"

class PlatformAdmin::AuditEventsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = PlatformAdminAccount.create!(
      email: "operator@example.com",
      password: "correct horse battery staple",
      otp_secret: "JBSWY3DPEHPK3PXP"
    )
    sign_in_platform_admin(@admin)
    PlatformAuditEvent.record!(action: "household.viewed", actor: @admin, target: households(:one))
  end

  test "the audit log filters have accessible names" do
    get platform_admin_audit_events_path

    assert_select "select#action_name[aria-label='Action']"
    assert_select "select#admin_id[aria-label='Operator']"
  end

  # @card-48.1
  test "operator can inspect the recent audit log" do
    get platform_admin_audit_events_path

    assert_response :success
    assert_select "h1", text: "Platform audit log"
    assert_includes response.body, "Household viewed"
    assert_includes response.body, @admin.email
  end

  # @card-48.1
  test "operator can filter audit log to hide page views" do
    PlatformAuditEvent.record!(action: "household.suspended", actor: @admin, target: households(:one), metadata: { reason: "Terms violation" })

    get platform_admin_audit_events_path(hide_views: "1")

    assert_response :success
    assert_select "[data-audit-action='household.suspended']", count: 1
    assert_select "[data-audit-action='household.viewed']", count: 0
    assert_includes response.body, "Terms violation"
  end

  # @card-48.1
  test "operator can filter audit log by category and search" do
    PlatformAuditEvent.record!(action: "platform_admin.signed_in", actor: @admin, metadata: { email: @admin.email })
    PlatformAuditEvent.record!(action: "support_thread.replied", actor: @admin, metadata: { note: "Resolved billing issue" })

    # Category filter
    get platform_admin_audit_events_path(category: "auth")
    assert_response :success
    assert_select "[data-audit-action='platform_admin.signed_in']"
    assert_select "[data-audit-action='support_thread.replied']", count: 0

    # Search filter
    get platform_admin_audit_events_path(q: "billing")
    assert_response :success
    assert_select "[data-audit-action='support_thread.replied']", count: 1
    assert_includes response.body, "Resolved billing issue"
  end

  private

  def sign_in_platform_admin(admin)
    post platform_admin_session_path, params: {
      email: admin.email,
      password: "correct horse battery staple",
      otp_code: PlatformAdminAccount::Totp.code(admin.otp_secret)
    }
  end
end
