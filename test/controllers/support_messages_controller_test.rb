require "test_helper"

class SupportMessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "customer@example.com", password: "customer-password")
    @member = family_members(:one)
    @member.update!(user: @user)
    @thread = SupportThread.create!(household: households(:one), created_by_user: @user, subject: "Calendar help")
    @thread.messages.create!(user: @user, body: "My calendar is not updating.")
    post session_path, params: { email: @user.email, password: "customer-password" }
  end

  test "blank reply does not claim the message was sent" do
    assert_no_difference -> { @thread.messages.count } do
      post support_thread_messages_path(@thread), params: { support_message: { body: "" } }
    end

    assert_redirected_to support_thread_path(@thread)
    assert_equal "We could not send that reply. Please try again.", flash[:alert]
    assert_not_equal "Your reply has been sent.", flash[:notice]
  end
end
