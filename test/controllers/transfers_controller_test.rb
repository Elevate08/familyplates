require "test_helper"

class TransfersControllerTest < ActionDispatch::IntegrationTest
  test "show displays profile for valid transfer link" do
    member = family_members(:one)
    token = member.transfer_id

    get transfer_path(token: token)
    assert_response :success
    assert_select "h1", text: /Claim Profile: #{member.name}/
  end

  test "show rejects invalid or expired transfer token" do
    get transfer_path(token: "invalid-token")
    assert_redirected_to select_profile_path
    assert_equal "This transfer link is invalid or has expired.", flash[:alert]
  end

  test "claim redirects unauthenticated user to sign in" do
    member = family_members(:two)
    token = member.transfer_id

    post claim_transfer_path(token: token)
    assert_redirected_to new_session_path
  end

  test "claim attaches profile to signed-in user" do
    user = User.create!(email: "newparent@example.com", password: "password123")
    post session_path, params: { email: user.email, password: "password123" }

    member = family_members(:two) # Mom in Spencer Family, has user_id: nil
    token = member.transfer_id

    post claim_transfer_path(token: token)

    assert_redirected_to root_url
    assert_equal user.id, member.reload.user_id
    assert cookies[:active_family_member_id].present?
  end

  test "claim prevents user from having two profiles in same household" do
    user = User.create!(email: "parent@example.com", password: "password123")
    member1 = family_members(:one)
    member1.update!(user: user)

    post session_path, params: { email: user.email, password: "password123" }

    member2 = family_members(:two)
    token = member2.transfer_id

    post claim_transfer_path(token: token)
    assert_redirected_to root_url
    assert_equal "You already have an active profile in this household.", flash[:alert]
    assert_nil member2.reload.user_id
  end
end
