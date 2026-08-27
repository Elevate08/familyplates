require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @admin = family_members(:one) # admin
    @member = family_members(:two) # member
  end

  test "should redirect unauthenticated users to login" do
    get admin_root_url
    assert_redirected_to new_session_url
  end

  test "should redirect non-admin family members to root with alert" do
    sign_in_as(@user)
    post set_profile_url(@member)

    get admin_root_url
    assert_redirected_to root_url
    assert_equal "Access restricted to household organizers / admins.", flash[:alert]
  end

  test "should allow admin family member to access dashboard" do
    sign_in_as(@user)
    post set_profile_url(@admin), params: { pin: "1234" }

    get admin_root_url
    assert_response :success
  end
end
