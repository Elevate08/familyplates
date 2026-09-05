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

  test "operator can inspect the recent audit log" do
    get platform_admin_audit_events_path

    assert_response :success
    assert_select "h1", text: "Platform audit log"
    assert_includes response.body, "Household viewed"
    assert_includes response.body, @admin.email
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
