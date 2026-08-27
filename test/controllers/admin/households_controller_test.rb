require "test_helper"

class Admin::HouseholdsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @household = households(:one)
    @admin = family_members(:one) # admin
    @member = family_members(:two) # member
  end

  test "should block non-admin" do
    sign_in_as(@user)
    post set_profile_url(@member)

    get edit_admin_household_url
    assert_redirected_to root_url
  end

  test "should get edit for admin" do
    sign_in_as(@user)
    post set_profile_url(@admin, params: { pin: "1234" })

    get edit_admin_household_url
    assert_response :success
  end

  test "should update household name" do
    sign_in_as(@user)
    post set_profile_url(@admin, params: { pin: "1234" })

    patch admin_household_url, params: {
      household: {
        name: "The Spencer Gourmet Kitchen"
      }
    }

    assert_redirected_to admin_root_url
    assert_equal "The Spencer Gourmet Kitchen", @household.reload.name
  end

  test "should regenerate calendar feed token" do
    sign_in_as(@user)
    post set_profile_url(@admin, params: { pin: "1234" })

    old_token = @household.calendar_token
    post regenerate_calendar_token_admin_household_url

    assert_redirected_to admin_root_url
    assert_not_equal old_token, @household.reload.calendar_token
  end
end
