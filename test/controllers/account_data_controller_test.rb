require "test_helper"

class AccountDataControllerTest < ActionDispatch::IntegrationTest
  setup do
    @previous_mode = FamilyPlates.config.mode
    @household = households(:one)
    @member = family_members(:one)
    @user = User.create!(email: "privacy@example.com")
    @member.update!(user: @user)
    sign_in_as(@member)
  end

  test "customer can download a safe household export" do
    get export_account_data_path

    assert_response :success
    assert_equal "application/json", response.media_type
    payload = JSON.parse(response.body)
    assert_equal @household.name, payload.dig("household", "name")
    assert_not_includes response.body, @household.join_code
    assert_not_includes response.body, "calendar_feed_token"
  end

  test "customer can request deletion once" do
    post request_deletion_account_data_path

    assert_redirected_to account_data_path
    assert_equal "pending", @household.account_deletion_requests.last.status
    assert_equal @user, @household.account_deletion_requests.last.requested_by_user

    post request_deletion_account_data_path
    assert_redirected_to account_data_path
    assert_equal 1, @household.account_deletion_requests.count
  end

  test "hosted households are warned that deletion cancels the subscription with no refund" do
    FamilyPlates.config.mode = "hosted"
    # Hosted mode signs in with a user session, not a bare profile cookie.
    session_record = @user.sessions.create!(token: SecureRandom.hex(32), kind: "browser")
    jar = ActionDispatch::Cookies::CookieJar.build(ActionDispatch::TestRequest.create, {})
    jar.signed[:session_token] = session_record.token
    jar.signed[:active_family_member_id] = @member.id
    cookies[:session_token] = jar[:session_token]
    cookies[:active_family_member_id] = jar[:active_family_member_id]

    get account_data_path

    assert_response :success
    assert_select "[data-testid='deletion-billing-warning']", text: /cancels your subscription immediately/
    assert_select "[data-testid='deletion-billing-warning']", text: /will not be charged again/
    assert_select "[data-testid='deletion-billing-warning']", text: /will not receive a refund/
  ensure
    FamilyPlates.config.mode = @previous_mode
  end

  test "non-admin profiles cannot export household data or request deletion" do
    sign_in_as(family_members(:two))

    get export_account_data_path
    assert_not_equal "application/json", response.media_type
    assert_response :redirect

    assert_no_difference -> { @household.account_deletion_requests.count } do
      post request_deletion_account_data_path
    end
  end
end
