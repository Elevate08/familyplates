require "test_helper"

class PlatformAdmin::PromotionProgramsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = PlatformAdminAccount.create!(email: "operator@example.com", password: "correct horse battery staple", otp_secret: "JBSWY3DPEHPK3PXP")
    sign_in_platform_admin(@admin)
  end

  test "operator can create and deactivate a promotion program" do
    post platform_admin_promotion_programs_path, params: { promotion_program: { name: "Launch", code: "launch", discount_percent: 20 } }
    assert_redirected_to platform_admin_promotion_programs_path
    program = PromotionProgram.last
    assert_equal "LAUNCH", program.code

    patch platform_admin_promotion_program_path(program), params: { promotion_program: { active: false } }
    assert_redirected_to platform_admin_promotion_programs_path
    assert_not program.reload.active?
  end

  private

  def sign_in_platform_admin(admin)
    post platform_admin_session_path, params: { email: admin.email, password: "correct horse battery staple", otp_code: PlatformAdminAccount::Totp.code(admin.otp_secret) }
  end
end
