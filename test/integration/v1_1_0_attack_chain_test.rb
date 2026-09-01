require "test_helper"

# The v1.1.1 checkpoint, as a test rather than a manual click-through.
#
# Each of these ran successfully against v1.1.0 on a seeded install with no
# credentials of any kind. They are kept together because the individual task
# tests each cover one link, and the thing that made v1.1.0 urgent was the chain.
class V110AttackChainTest < ActionDispatch::IntegrationTest
  setup do
    @admin = family_members(:one)
    @member = family_members(:two)
    assert Household.exists?, "precondition: a configured install, not first boot"
  end

  test "the full anonymous privilege escalation is closed end to end" do
    # 1. A member profile carries no PIN, so anyone can become a member. This is
    #    a deliberate product decision and still works - it is the starting point
    #    the rest of the chain used to build on.
    post set_profile_url(@member)
    assert signed_in_as?(@member)

    # 2. From there, v1.1.0 let a member rewrite the organizer's PIN.
    patch "/family_members/#{@admin.id}", params: { family_member: { pin: "0000" } }
    assert_response :not_found
    assert_equal "1234", @admin.reload.pin

    # 3. ...or mint a fresh admin through the onboarding wizard.
    assert_no_difference "FamilyMember.count" do
      post onboarding_add_member_url, params: {
        family_member: { name: "Mallory", role: "admin", pin: "9999", avatar_color: "#F97316", avatar_icon: "star" }
      }
    end

    # 4. ...or delete the roster.
    assert_no_difference "FamilyMember.count" do
      delete "/family_members/#{@admin.id}"
    end

    # The member never gained anything.
    assert signed_in_as?(@member)
    assert_not @member.reload.admin?
  end

  test "the same chain is closed to a visitor with no session at all" do
    assert_no_difference "FamilyMember.count" do
      post onboarding_add_member_url, params: {
        family_member: { name: "Mallory", role: "admin", pin: "9999", avatar_color: "#F97316", avatar_icon: "star" }
      }
    end
    assert_redirected_to select_profile_url

    patch "/family_members/#{@admin.id}", params: { family_member: { pin: "0000" } }
    assert_response :not_found
    assert_equal "1234", @admin.reload.pin
  end

  test "the organizer PIN cannot be brute forced" do
    (PinThrottling::MAX_ATTEMPTS + 1).times do
      post set_profile_url(@admin), params: { pin: "0000" }
    end

    assert_equal "Too many attempts. Please wait a few minutes and try again.", flash[:alert]
    assert_nil active_family_member_id

    # Even the right PIN gets nothing while throttled, so the response is not an
    # oracle for whether a guess was correct.
    post set_profile_url(@admin), params: { pin: @admin.pin }
    assert_nil active_family_member_id
  end

  test "the server will not fetch an internal address on request" do
    sign_in_as(@member)

    [ "http://169.254.169.254/latest/meta-data/",
      "http://127.0.0.1:3000/admin",
      "http://10.0.0.1/",
      "file:///etc/passwd",
      "ftp://example.com/secrets" ].each do |url|
      assert_no_difference "Recipe.count" do
        post recipe_imports_url, params: { url: url }
      end
      assert_equal "Could not fetch recipe from that web address. Please check the link or add manually.",
                   flash[:alert], "#{url} should have been refused"
    end
  end

  test "first boot still works, so none of this locked out a new install" do
    Household.destroy_all

    get onboarding_family_url
    assert_response :success

    post onboarding_save_family_url, params: {
      household: { name: "Fresh Kitchen", breakfast_time: "08:00", lunch_time: "12:30", dinner_time: "18:00" },
      admin_member: { name: "New Chef", pin: "4321", avatar_color: "#3B82F6", avatar_icon: "chef-hat" }
    }
    assert_redirected_to onboarding_members_url

    get onboarding_members_url
    assert_response :success
  end
end
