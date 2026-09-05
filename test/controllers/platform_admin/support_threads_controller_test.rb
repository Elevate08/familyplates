require "test_helper"

class PlatformAdmin::SupportThreadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "customer@example.com")
    @member = family_members(:one)
    @member.update!(user: @user)
    @thread = SupportThread.create!(household: households(:one), created_by_user: @user, subject: "Calendar help")
    @thread.messages.create!(user: @user, body: "My calendar is not updating.")
    @admin = PlatformAdminAccount.create!(email: "operator@example.com", password: "correct horse battery staple", otp_secret: "JBSWY3DPEHPK3PXP")
    sign_in_platform_admin(@admin)
  end

  test "operator can see threads across households and reply" do
    get platform_admin_support_threads_path
    assert_response :success
    assert_includes response.body, "Calendar help"

    get platform_admin_support_thread_path(@thread)
    assert_includes response.body, "My calendar is not updating."

    post reply_platform_admin_support_thread_path(@thread), params: { support_message: { body: "I am investigating this." } }
    assert_redirected_to platform_admin_support_thread_path(@thread)
    reply = @thread.messages.order(:created_at, :id).last
    assert_equal "I am investigating this.", reply.body
    assert_equal @admin, reply.platform_admin
  end

  test "operator can resolve a support thread and it moves to resolved section" do
    patch resolve_platform_admin_support_thread_path(@thread)

    assert_redirected_to platform_admin_support_thread_path(@thread)
    assert_equal "resolved", @thread.reload.status
    assert_not_nil @thread.resolved_at

    get platform_admin_support_threads_path
    assert_response :success
    assert_includes response.body, "Resolved Support Requests"
    assert_includes response.body, "Calendar help"

    get platform_admin_support_threads_path(status: :resolved)
    assert_response :success
    assert_includes response.body, "Calendar help"
  end

  test "operator can reopen a resolved thread" do
    @thread.resolve!
    assert @thread.resolved?

    patch reopen_platform_admin_support_thread_path(@thread)
    assert_redirected_to platform_admin_support_thread_path(@thread)
    assert_equal "waiting_on_customer", @thread.reload.status
    assert_nil @thread.resolved_at
  end

  test "operator can manually change status" do
    patch change_status_platform_admin_support_thread_path(@thread), params: { status: "waiting_on_customer" }
    assert_redirected_to platform_admin_support_thread_path(@thread)
    assert_equal "waiting_on_customer", @thread.reload.status

    patch change_status_platform_admin_support_thread_path(@thread), params: { status: "waiting_on_support" }
    assert_redirected_to platform_admin_support_thread_path(@thread)
    assert_equal "waiting_on_support", @thread.reload.status
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
