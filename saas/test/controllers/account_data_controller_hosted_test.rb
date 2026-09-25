require "test_helper"

class AccountDataControllerHostedTest < ActionDispatch::IntegrationTest
  setup do
    @previous_mode = FamilyPlates.config.mode
    @household = households(:one)
    @member = family_members(:one)
    @user = User.create!(email: "privacy@example.com")
    @member.update!(user: @user)
    sign_in_as(@member)
  end

  # @card-47.2
  test "customer can request deletion once" do
    post request_deletion_account_data_path

    assert_redirected_to account_data_path
    assert_equal "pending", @household.account_deletion_requests.last.status
    assert_equal @user, @household.account_deletion_requests.last.requested_by_user

    post request_deletion_account_data_path
    assert_redirected_to account_data_path
    assert_equal 1, @household.account_deletion_requests.count
  end

  # @card-47.2
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


  # @card-47.1
  test "non-admin profiles cannot request deletion" do
    sign_in_as(family_members(:two))

    assert_no_difference -> { @household.account_deletion_requests.count } do
      post request_deletion_account_data_path
    end
  end
end
