require "test_helper"

class PlatformAdmin::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = PlatformAdminAccount.create!(
      email: "operator@example.com",
      password: "correct horse battery staple",
      otp_secret: "JBSWY3DPEHPK3PXP"
    )
  end

  test "requires platform-admin authentication" do
    get platform_admin_root_path

    assert_redirected_to new_platform_admin_session_path
  end

  test "household users cannot access the platform-admin console" do
    sign_in_as(family_members(:one))

    get platform_admin_root_path

    assert_redirected_to new_platform_admin_session_path
  end

  test "authenticated platform admin sees the operator console" do
    sign_in_platform_admin(@admin)

    get platform_admin_root_path

    assert_response :success
    assert_select "link[rel='stylesheet']"
    assert_select "nav a[href='#{platform_admin_households_path}']"
    assert_select "h1", text: /Platform Operator Console/i
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
