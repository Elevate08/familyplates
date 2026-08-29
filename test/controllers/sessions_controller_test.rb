require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "new redirects to select_profile_path" do
    get new_session_path
    assert_redirected_to select_profile_path
  end

  test "destroy clears active profile and redirects to select_profile_path" do
    sign_in_as(family_members(:one))

    delete session_path

    assert_redirected_to select_profile_path
    assert cookies[:active_family_member_id].blank?
  end
end
