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

  test "should allow admin member to update their 4-digit PIN when providing current PIN" do
    sign_in_as(@admin_member)

    patch preferences_url, params: {
      current_pin: "1234",
      family_member: {
        pin: "4321"
      }
    }

    assert_redirected_to edit_preferences_url
    @admin_member.reload
    assert @admin_member.verify_pin("4321")
    assert @admin_member.requires_pin?
  end

  test "admin updating name, color, or icon requires valid current PIN" do
    sign_in_as(@admin_member)

    # 1. Without current PIN -> rejected with error
    patch preferences_url, params: {
      family_member: {
        name: "Hacked Admin",
        avatar_color: "#10B981"
      }
    }
    assert_response :unprocessable_entity
    assert_includes response.body, "Please enter your current 4-digit PIN to confirm changes"
    @admin_member.reload
    assert_not_equal "Hacked Admin", @admin_member.name

    # 2. With incorrect current PIN -> rejected with error
    patch preferences_url, params: {
      current_pin: "0000",
      family_member: {
        name: "Hacked Admin",
        avatar_color: "#10B981"
      }
    }
    assert_response :unprocessable_entity
    assert_includes response.body, "Incorrect 4-digit PIN. Changes were not saved."
    @admin_member.reload
    assert_not_equal "Hacked Admin", @admin_member.name

    # 3. With correct current PIN -> succeeds and updates profile
    patch preferences_url, params: {
      current_pin: "1234",
      family_member: {
        name: "Papa Bear",
        avatar_color: "#10B981",
        avatar_icon: "flame"
      }
    }
    assert_redirected_to edit_preferences_url
    assert_equal "Your preferences were saved successfully! 🎨", flash[:notice]
    @admin_member.reload
    assert_equal "Papa Bear", @admin_member.name
    assert_equal "#10B981", @admin_member.avatar_color
    assert_equal "flame", @admin_member.avatar_icon
    assert @admin_member.verify_pin("1234"), "PIN remains unchanged when only updating profile details"
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
    assert_nil @regular_member.pin_digest
    assert_not @regular_member.requires_pin?
  end

  test "the PIN field shows a Configured badge for an admin who has one" do
    sign_in_as(@admin_member)

    get edit_preferences_path

    assert_select "[data-controller=configured-field]", 1
    assert_select "[data-configured-field-target=indicator]", 1
    assert_not_includes response.body, "unchanged", "the badge replaced the placeholder wording"
  end

  test "a member with no PIN sees no PIN field at all" do
    sign_in_as(@regular_member)

    get edit_preferences_path

    assert_select "[data-configured-field-target=indicator]", 0
  end

  test "repeated wrong PIN attempts when saving preferences are throttled" do
    sign_in_as(@admin_member)

    (PinThrottling::MAX_ATTEMPTS - 1).times do
      patch preferences_url, params: {
        current_pin: "0000",
        family_member: { name: "New Name" }
      }
      assert_response :unprocessable_entity
    end

    # Next attempt should be throttled
    patch preferences_url, params: {
      current_pin: "1234",
      family_member: { name: "New Name" }
    }
    assert_redirected_to edit_preferences_path
    assert_equal "Too many attempts. Please wait a few minutes and try again.", flash[:alert]
  end
end
