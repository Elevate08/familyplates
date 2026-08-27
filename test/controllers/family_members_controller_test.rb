require "test_helper"

class FamilyMembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @household = households(:one)
    @family_member = family_members(:one)
    sign_in_as(@user)
  end

  test "should get index" do
    get family_members_url
    assert_response :success
  end

  test "should create family member" do
    assert_difference("FamilyMember.count", 1) do
      post family_members_url, params: {
        family_member: { name: "Little Timmy", avatar_color: "#10B981", role: "member" }
      }
    end

    assert_redirected_to family_members_url
  end

  test "should switch active family member" do
    target_member = family_members(:two)
    post switch_family_member_url(target_member)
    assert_response :redirect
  end

  test "should delete family member" do
    target_member = family_members(:two)
    assert_difference("FamilyMember.count", -1) do
      delete family_member_url(target_member)
    end
    assert_redirected_to family_members_url
  end
end
