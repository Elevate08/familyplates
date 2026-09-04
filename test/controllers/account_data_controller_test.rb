require "test_helper"

class AccountDataControllerTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @member = @household.family_members.first
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
end
