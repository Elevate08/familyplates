require "test_helper"

class Admin::AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @admin = family_members(:one) # admin
    @member = family_members(:two) # member
  end

  test "should block non-admin" do
    sign_in_as(@user)
    post set_profile_url(@member)

    get edit_admin_account_url
    assert_redirected_to root_url
  end

  test "should get edit for admin" do
    sign_in_as(@user)
    post set_profile_url(@admin, params: { pin: "1234" })

    get edit_admin_account_url
    assert_response :success
  end

  test "should update primary email address without changing password" do
    sign_in_as(@user)
    post set_profile_url(@admin, params: { pin: "1234" })

    patch admin_account_url, params: {
      user: {
        email_address: "spencer.family@example.com",
        password: "",
        password_confirmation: ""
      }
    }

    assert_redirected_to admin_root_url
    assert_equal "spencer.family@example.com", @user.reload.email_address
    assert @user.authenticate("password")
  end

  test "should update password" do
    sign_in_as(@user)
    post set_profile_url(@admin, params: { pin: "1234" })

    patch admin_account_url, params: {
      user: {
        email_address: @user.email_address,
        password: "newsecretpassword",
        password_confirmation: "newsecretpassword"
      }
    }

    assert_redirected_to admin_root_url
    assert @user.reload.authenticate("newsecretpassword")
  end
end
