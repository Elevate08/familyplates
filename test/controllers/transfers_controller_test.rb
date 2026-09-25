require "test_helper"

class TransfersControllerTest < ActionDispatch::IntegrationTest
  # @card-16.5
  test "show displays profile for valid transfer link" do
    member = family_members(:one)
    token = member.transfer_id

    get transfer_path(token: token)
    assert_response :success
    assert_select "h1", text: /Claim Profile: #{member.name}/
  end

  # @card-16.5
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

  # @card-16.5
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

  # @card-16.5
  test "a claimed transfer link cannot be replayed to take over the profile" do
    member = family_members(:two)
    token = member.transfer_id
    first_user = User.create!(email: "first@example.com", password: "password123")
    second_user = User.create!(email: "second@example.com", password: "password123")

    post session_path, params: { email: first_user.email, password: "password123" }
    post claim_transfer_path(token: token)
    assert_equal first_user, member.reload.user

    delete session_path
    post session_path, params: { email: second_user.email, password: "password123" }
    post claim_transfer_path(token: token)

    assert_redirected_to select_profile_path
    assert_equal first_user, member.reload.user
  end

  # @card-14.3
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
