require "test_helper"

class SuspensionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @user = User.create!(email: "suspended@example.com")
    @household.family_members.create!(name: "Suspended Admin", role: "admin", pin: "1234", user: @user)
    sign_in_user(@user)
    @household.update!(suspended_at: Time.current, suspension_reason: "Payment review")
  end

  test "signed-in suspended household sees status and support link" do
    get root_path

    assert_redirected_to suspended_path
    get suspended_path

    assert_response :success
    assert_includes response.body, "This household is suspended"
    assert_includes response.body, "Payment review"
    assert_select "a[href='#{support_threads_path}']", text: "Contact support"
  end

  test "suspended household can open support" do
    get support_threads_path

    assert_response :success
  end

  private

  def sign_in_user(user)
    session_record = user.sessions.create!(token: SecureRandom.hex(32), kind: "browser")
    jar = ActionDispatch::Cookies::CookieJar.build(ActionDispatch::TestRequest.create, {})
    jar.signed[:session_token] = session_record.token
    cookies[:session_token] = jar[:session_token]
    jar.signed[:active_family_member_id] = @household.family_members.last.id
    cookies[:active_family_member_id] = jar[:active_family_member_id]
  end
end
