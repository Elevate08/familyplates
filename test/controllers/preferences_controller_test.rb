require "test_helper"

class PreferencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin_member = family_members(:one) # role: admin
    @regular_member = family_members(:two) # role: member
  end

  test "should redirect to profile selection when unauthenticated" do
    get edit_preferences_url
    assert_redirected_to select_profile_url
  end

  test "should get edit when authenticated" do
    sign_in_as(@admin_member)
    get edit_preferences_url
    assert_response :success
  end

  test "should update name, avatar color, and avatar icon for active member" do
    sign_in_as(@regular_member)

    patch preferences_url, params: {
      family_member: {
        name: "Chef Mom",
        avatar_color: "#10B981",
        avatar_icon: "flame"
      }
    }

    assert_redirected_to edit_preferences_url
    assert_equal "Your preferences were saved successfully! 🎨", flash[:notice]

    @regular_member.reload
    assert_equal "Chef Mom", @regular_member.name
    assert_equal "#10B981", @regular_member.avatar_color
    assert_equal "flame", @regular_member.avatar_icon
  end

  test "should allow admin member to update their 4-digit PIN" do
    sign_in_as(@admin_member)

    patch preferences_url, params: {
      family_member: {
        pin: "4321"
      }
    }

    assert_redirected_to edit_preferences_url
    @admin_member.reload
    assert_equal "4321", @admin_member.pin
    assert @admin_member.requires_pin?
  end

  test "should not allow non-admin member to set a PIN" do
    sign_in_as(@regular_member)

    patch preferences_url, params: {
      family_member: {
        pin: "9999"
      }
    }

    assert_redirected_to edit_preferences_url
    @regular_member.reload
    assert_nil @regular_member.pin
    assert_not @regular_member.requires_pin?
  end
end
