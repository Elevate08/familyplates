require "test_helper"

class SupportThreadTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
    @user = User.create!(email: "customer@example.com")
    @member = family_members(:one)
    @member.update!(user: @user)
    @admin = PlatformAdminAccount.create!(email: "operator@example.com", password: "correct horse battery staple", otp_secret: "JBSWY3DPEHPK3PXP")
  end

  test "customer and platform admin messages share one ordered conversation" do
    thread = SupportThread.create!(household: @household, created_by_user: @user, subject: "Calendar help")
    customer_message = thread.messages.create!(user: @user, body: "My calendar is not updating.")
    operator_message = thread.messages.create!(platform_admin: @admin, body: "I am looking into this.")

    assert_equal [ customer_message, operator_message ], thread.messages.order(:created_at, :id)
    assert_equal @user, customer_message.author
    assert_equal @admin, operator_message.author
    assert_equal "waiting_on_customer", thread.reload.status
  end

  test "messages require exactly one author" do
    thread = SupportThread.create!(household: @household, subject: "Question")

    assert_not thread.messages.build(body: "Missing author").valid?
    assert_not thread.messages.build(user: @user, platform_admin: @admin, body: "Two authors").valid?
  end

  test "resolving and replying update thread status" do
    thread = SupportThread.create!(household: @household, subject: "Question", status: "waiting_on_support")
    thread.resolve!
    assert_equal "resolved", thread.reload.status

    thread.messages.create!(platform_admin: @admin, body: "Follow-up")
    assert_equal "waiting_on_customer", thread.reload.status
  end
end
