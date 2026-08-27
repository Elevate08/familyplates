require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "should get select" do
    get select_profile_url
    assert_response :success
  end

  test "should set non-admin profile without pin" do
    member = family_members(:two)
    post set_profile_url(member)

    assert_redirected_to root_url
    assert_not_nil cookies[:active_family_member_id]
  end

  test "should set admin profile with valid pin" do
    admin = family_members(:one)
    admin.update!(pin: "1234")

    post set_profile_url(admin), params: { pin: "1234" }

    assert_redirected_to root_url
    assert_not_nil cookies[:active_family_member_id]
  end

  test "should reject admin profile with invalid pin" do
    admin = family_members(:one)
    admin.update!(pin: "1234")

    post set_profile_url(admin), params: { pin: "9999" }

    assert_redirected_to select_profile_url(pin_member_id: admin.id)
    assert_equal "Incorrect 4-digit PIN for #{admin.name}.", flash[:alert]
  end

  test "should reject admin profile with blank pin" do
    admin = family_members(:one)
    admin.update!(pin: "1234")

    post set_profile_url(admin), params: { pin: "" }

    assert_redirected_to select_profile_url(pin_member_id: admin.id)
    assert_equal "This profile is protected by a PIN.", flash[:alert]
  end

  test "should redirect to select profile if logged in but no active profile selected" do
    # When user signs in and has not selected a profile yet
    cookies.delete("active_family_member_id")
    Current.family_member = nil

    get root_url
    assert_redirected_to select_profile_url
    assert_equal "Please select who is in the kitchen today.", flash[:alert]
  end
end
