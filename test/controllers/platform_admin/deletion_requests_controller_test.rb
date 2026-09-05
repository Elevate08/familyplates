require "test_helper"

class PlatformAdmin::DeletionRequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = PlatformAdminAccount.create!(email: "operator@example.com", password: "correct horse battery staple", otp_secret: "JBSWY3DPEHPK3PXP")
    @household = Household.create!(name: "Delete Me Kitchen")
    @user = User.create!(email: "delete-me@example.com")
    @household.family_members.create!(name: "Delete Admin", role: "admin", pin: "1234", user: @user)
    @deletion_request = @household.account_deletion_requests.create!(requested_by_user: @user, requested_at: Time.current)
    sign_in_platform_admin(@admin)
  end

  test "permanent deletion requires exact household-name confirmation" do
    delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: "wrong" }

    assert_redirected_to platform_admin_deletion_requests_path
    assert Household.exists?(@household.id)

    delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }

    assert_redirected_to platform_admin_deletion_requests_path
    assert_not Household.exists?(@household.id)
    assert_not User.exists?(@user.id)
    assert PlatformAuditEvent.exists?(action: "household.permanently_deleted", target_id: @household.id)
  end

  test "permanent deletion succeeds even when Stripe subscription cancellation raises Stripe error" do
    customer = @household.set_payment_processor(:stripe, allow_fake: true, processor_id: "cus_del_#{SecureRandom.hex(6)}")
    customer.subscriptions.create!(
      name: "default",
      processor_id: "sub_sim_missing_123",
      processor_plan: "monthly",
      status: "active",
      current_period_start: Time.current,
      current_period_end: 1.month.from_now
    )

    delete platform_admin_deletion_request_path(@deletion_request), params: { confirmation: @household.name }

    assert_redirected_to platform_admin_deletion_requests_path
    assert_not Household.exists?(@household.id)
    assert_not User.exists?(@user.id)
    assert PlatformAuditEvent.exists?(action: "household.permanently_deleted", target_id: @household.id)
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
