require "test_helper"

class SupportThreadsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "customer@example.com", password: "customer-password")
    @member = family_members(:one)
    @member.update!(user: @user)
    @admin = PlatformAdminAccount.create!(email: "operator@example.com", password: "correct horse battery staple", otp_secret: "JBSWY3DPEHPK3PXP")
    post session_path, params: { email: @user.email, password: "customer-password" }
  end

  test "customer can start and continue a support conversation" do
    post support_threads_path, params: { support_thread: { subject: "Calendar help", body: "My calendar is not updating." } }

    assert_redirected_to support_thread_path(SupportThread.last)
    assert_equal "My calendar is not updating.", SupportMessage.last.body

    post support_thread_messages_path(SupportThread.last), params: { support_message: { body: "It still is not updating." } }
    assert_redirected_to support_thread_path(SupportThread.last)
    assert_equal 2, SupportThread.last.messages.count
  end

  test "customer only sees support threads in their household" do
    thread = SupportThread.create!(household: households(:one), subject: "Visible")
    other_household = Household.create!(name: "Other Household")
    SupportThread.create!(household: other_household, subject: "Hidden")

    get support_threads_path

    assert_includes response.body, "Visible"
    assert_not_includes response.body, "Hidden"

    get support_thread_path(thread)
    assert_response :success
  end

  test "customer can resolve a support thread and it moves to resolved section" do
    thread = SupportThread.create!(household: households(:one), created_by_user: @user, subject: "Need recipe help")
    thread.messages.create!(user: @user, body: "How do I import?")

    get support_threads_path
    assert_includes response.body, "Active conversations"

    patch resolve_support_thread_path(thread)
    assert_redirected_to support_thread_path(thread)
    assert_equal "resolved", thread.reload.status

    get support_threads_path
    assert_includes response.body, "Resolved requests"
    assert_includes response.body, "Need recipe help"

    # Customer replies to resolved thread -> automatically reopens as waiting_on_support
    post support_thread_messages_path(thread), params: { support_message: { body: "Actually I have another question." } }
    assert_redirected_to support_thread_path(thread)
    assert_equal "waiting_on_support", thread.reload.status
  end
end
