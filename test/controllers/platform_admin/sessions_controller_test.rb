require "test_helper"

class PlatformAdmin::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = PlatformAdminAccount.create!(
      email: "operator@example.com",
      password: "correct horse battery staple",
      otp_secret: "JBSWY3DPEHPK3PXP"
    )
  end

  test "login requires password and current MFA code" do
    get new_platform_admin_session_path
    assert_response :success

    post platform_admin_session_path, params: {
      email: @admin.email,
      password: "correct horse battery staple",
      otp_code: PlatformAdminAccount::Totp.code(@admin.otp_secret)
    }

    assert_redirected_to platform_admin_root_path
    assert cookies[:platform_admin_session_token].present?
  end

  test "invalid credentials do not create a platform-admin session" do
    post platform_admin_session_path, params: {
      email: @admin.email,
      password: "wrong password",
      otp_code: "000000"
    }

    assert_response :unprocessable_entity
    assert_equal "Invalid email, password, or verification code.", flash[:alert]
    assert_nil cookies[:platform_admin_session_token]
  end

  test "authenticated platform admin can sign out" do
    sign_in_platform_admin(@admin)

    delete platform_admin_session_path

    assert_redirected_to new_platform_admin_session_path
    assert cookies[:platform_admin_session_token].blank?
    assert_not PlatformAdminSession.exists?
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
