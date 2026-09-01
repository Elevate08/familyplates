require "test_helper"

class FamilyMembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @admin = family_members(:one)
    @member = family_members(:two)
  end

  test "should get index" do
    sign_in_as(@admin)
    get family_members_url
    assert_response :success
  end

  test "index offers admins the control center and members only their preferences" do
    sign_in_as(@admin)
    get family_members_url
    assert_select "a[href=?]", admin_family_members_path

    sign_in_as(@member)
    get family_members_url
    assert_select "a[href=?]", admin_family_members_path, count: 0
    assert_select "a[href=?]", edit_preferences_path
  end

  test "should switch active family member" do
    sign_in_as(@admin)
    post switch_family_member_url(@member)
    assert_response :redirect
    assert signed_in_as?(@member)
  end

  test "should require PIN when switching to admin member" do
    sign_in_as(@member)

    post switch_family_member_url(@admin)
    assert_redirected_to select_profile_url(pin_member_id: @admin.id)
    assert_equal "Please enter the 4-digit PIN for #{@admin.name}.", flash[:alert]
    assert signed_in_as?(@member), "a failed switch must leave the current profile alone"

    post switch_family_member_url(@admin), params: { pin: "1234" }
    assert_response :redirect
    assert signed_in_as?(@admin)
  end

  # --- Roster mutation is not reachable here ---------------------------------
  #
  # These verbs used to live on this controller with no admin check at all, so a
  # member — and a member profile needs no PIN, meaning anyone at all — could
  # PATCH an organizer's PIN and then switch into their profile. Roster changes
  # now happen only in Admin::FamilyMembersController.

  # family_member_url no longer exists as a route helper, which is itself the
  # point; these drive the raw paths an attacker would.
  test "a member cannot rewrite an organizer's PIN here" do
    sign_in_as(@member)

    patch "/family_members/#{@admin.id}", params: { family_member: { pin: "0000" } }

    assert_response :not_found
    assert_equal "1234", @admin.reload.pin
  end

  test "a member cannot delete a family member here" do
    sign_in_as(@member)

    assert_no_difference "FamilyMember.count" do
      delete "/family_members/#{@admin.id}"
    end

    assert_response :not_found
  end

  test "even an admin cannot create a family member here" do
    sign_in_as(@admin)

    assert_no_difference "FamilyMember.count" do
      post family_members_url, params: { family_member: { name: "Little Timmy", avatar_color: "#10B981", role: "member" } }
    end

    assert_response :not_found
  end

  test "an anonymous visitor cannot rewrite an organizer's PIN here" do
    patch "/family_members/#{@admin.id}", params: { family_member: { pin: "0000" } }

    assert_response :not_found
    assert_equal "1234", @admin.reload.pin
  end

  test "roster mutation is still available to admins in the control center" do
    sign_in_as(@admin)

    assert_difference "FamilyMember.count", 1 do
      post admin_family_members_url, params: { family_member: { name: "Little Timmy", avatar_color: "#10B981", role: "member" } }
    end

    assert_redirected_to admin_family_members_url
  end
end
