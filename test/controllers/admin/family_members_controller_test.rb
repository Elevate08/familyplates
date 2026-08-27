require "test_helper"

class Admin::FamilyMembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @admin = family_members(:one) # admin
    @member = family_members(:two) # member
  end

  test "should block non-admin from accessing index" do
    sign_in_as(@user)
    post set_profile_url(@member)

    get admin_family_members_url
    assert_redirected_to root_url
  end

  test "should get index for admin" do
    sign_in_as(@user)
    post set_profile_url(@admin, params: { pin: "1234" })

    get admin_family_members_url
    assert_response :success
  end

  test "should create member for admin" do
    sign_in_as(@user)
    post set_profile_url(@admin, params: { pin: "1234" })

    assert_difference "FamilyMember.count", 1 do
      post admin_family_members_url, params: {
        family_member: {
          name: "Little Alex",
          role: "member",
          avatar_color: "#10B981",
          avatar_icon: "smile"
        }
      }
    end

    assert_redirected_to admin_family_members_url
    new_member = FamilyMember.last
    assert_equal "Little Alex", new_member.name
    assert_equal "member", new_member.role
    assert_nil new_member.pin
  end

  test "should create admin with PIN" do
    sign_in_as(@user)
    post set_profile_url(@admin, params: { pin: "1234" })

    assert_difference "FamilyMember.count", 1 do
      post admin_family_members_url, params: {
        family_member: {
          name: "Grandpa Admin",
          role: "admin",
          avatar_color: "#8B5CF6",
          avatar_icon: "award",
          pin: "7890"
        }
      }
    end

    assert_redirected_to admin_family_members_url
    new_admin = FamilyMember.last
    assert_equal "Grandpa Admin", new_admin.name
    assert_equal "admin", new_admin.role
    assert_equal "7890", new_admin.pin
    assert new_admin.requires_pin?
  end

  test "should update family member" do
    sign_in_as(@user)
    post set_profile_url(@admin, params: { pin: "1234" })

    patch admin_family_member_url(@member), params: {
      family_member: {
        name: "Mom Extraordinaire",
        avatar_icon: "sparkles"
      }
    }

    assert_redirected_to admin_family_members_url
    assert_equal "Mom Extraordinaire", @member.reload.name
    assert_equal "sparkles", @member.avatar_icon
  end

  test "should reset admin PIN with valid 4-digit PIN" do
    sign_in_as(@user)
    post set_profile_url(@admin, params: { pin: "1234" })

    # Set new PIN
    patch reset_pin_admin_family_member_url(@admin), params: { pin: "9876" }
    assert_redirected_to admin_family_members_url
    assert_equal "9876", @admin.reload.pin
    assert @admin.requires_pin?
  end

  test "should reject admin PIN reset with invalid or blank PIN" do
    sign_in_as(@user)
    post set_profile_url(@admin, params: { pin: "1234" })

    # Attempt blank PIN
    patch reset_pin_admin_family_member_url(@admin), params: { pin: "" }
    assert_redirected_to admin_family_members_url
    assert_equal "A valid 4-digit PIN is required for admin profiles.", flash[:alert]
    assert_equal "1234", @admin.reload.pin
  end

  test "should reject PIN reset for non-admin" do
    sign_in_as(@user)
    post set_profile_url(@admin, params: { pin: "1234" })

    patch reset_pin_admin_family_member_url(@member), params: { pin: "1234" }
    assert_redirected_to admin_family_members_url
    assert_equal "Non-admin members do not have a PIN.", flash[:alert]
    assert_nil @member.reload.pin
  end

  test "should destroy member but protect last admin" do
    sign_in_as(@user)
    post set_profile_url(@admin, params: { pin: "1234" })

    # Destroy regular member should work
    assert_difference "FamilyMember.count", -1 do
      delete admin_family_member_url(@member)
    end
    assert_redirected_to admin_family_members_url

    # Attempting to destroy only remaining admin should fail
    assert_no_difference "FamilyMember.count" do
      delete admin_family_member_url(@admin)
    end
    assert_redirected_to admin_family_members_url
    assert_equal "Your household must have at least one family member.", flash[:alert]
  end
end
