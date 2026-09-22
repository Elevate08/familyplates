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
    assert_select "link[rel='stylesheet']"
    assert_select "nav", text: /Operator/i

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
    assert_includes response.body, "Invalid email, password, or verification code."
    assert_nil cookies[:platform_admin_session_token]
  end

  test "dummy bcrypt work is spent whenever the real password check is skipped" do
    dummy_calls = []
    password_class = BCrypt::Password.singleton_class
    original = password_class.instance_method(:create)
    password_class.define_method(:create) do |*args, **kwargs, &block|
      dummy_calls << kwargs
      original.bind_call(self, *args, **kwargs, &block)
    end

    post platform_admin_session_path, params: {
      email: @admin.email,
      password: "wrong password",
      otp_code: "000000"
    }
    assert_empty dummy_calls

    post platform_admin_session_path, params: {
      email: "nobody@example.com",
      password: "wrong password",
      otp_code: "000000"
    }
    assert_equal 1, dummy_calls.size
    assert_equal BCrypt::Engine::MIN_COST, dummy_calls.first[:cost]

    @admin.update!(active: false)
    post platform_admin_session_path, params: {
      email: @admin.email,
      password: "correct horse battery staple",
      otp_code: PlatformAdminAccount::Totp.code(@admin.otp_secret)
    }
    assert_equal 2, dummy_calls.size, "a deactivated admin must cost the same bcrypt work as an unknown email"
    assert_response :unprocessable_entity
  ensure
    password_class.define_method(:create, original)
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
