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

  # @card-47.1
  test "customer can download a safe household export" do
    get export_account_data_path

    assert_response :success
    assert_equal "application/json", response.media_type
    payload = JSON.parse(response.body)
    assert_equal @household.name, payload.dig("household", "name")
    assert_not_includes response.body, @household.join_code
    assert_not_includes response.body, "calendar_feed_token"
  end

  # @card-47.1
  test "non-admin profiles cannot export household data" do
    sign_in_as(family_members(:two))

    get export_account_data_path
    assert_not_equal "application/json", response.media_type
    assert_response :redirect
  end

  test "an appliance offers export but no deletion request, having no operator to send one to" do
    sign_in_as(family_members(:one))

    get account_data_path

    assert_response :success
    assert_select "a[href=?]", export_account_data_path
    assert_select "form[action$='/request_deletion']", false
  end
end
