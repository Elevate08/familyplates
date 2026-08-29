require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = family_members(:one) # admin
    @member = family_members(:two) # member
  end

  test "should redirect unauthenticated users to profile selection" do
    get admin_root_url
    assert_redirected_to select_profile_url
  end

  test "should redirect non-admin family members to root with alert" do
    sign_in_as(@member)

    get admin_root_url
    assert_redirected_to root_url
    assert_equal "Access restricted to household organizers / admins.", flash[:alert]
  end

  test "should allow admin family member to access dashboard" do
    sign_in_as(@admin)

    get admin_root_url
    assert_response :success
  end
end
