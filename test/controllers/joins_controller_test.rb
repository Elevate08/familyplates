require "test_helper"

class JoinsControllerTest < ActionDispatch::IntegrationTest
  test "new renders join code entry form" do
    get join_path
    assert_response :success
    assert_select "h1", text: /Join a Household/
  end

  test "create with invalid join code renders 422" do
    post join_path, params: { join_code: "INVALID-CODE" }
    assert_response :unprocessable_entity
    assert_equal "Invalid join code. Please check the code and try again.", flash[:alert]
  end

  test "create with valid join code redirects unauthenticated user to sign in" do
    household = households(:two)

    post join_path, params: { join_code: household.join_code }

    assert_redirected_to new_session_path
    assert_equal household.join_code, session[:pending_join_code]
  end

  test "create with valid join code adds signed-in user as family member" do
    user = User.create!(email: "joining_parent@example.com", password: "password123")
    post session_path, params: { email: user.email, password: "password123" }

    household = households(:two)

    assert_difference -> { household.family_members.count }, 1 do
      post join_path, params: { join_code: household.join_code, name: "New Parent" }
    end

    assert_redirected_to root_url
    new_member = household.family_members.find_by(name: "New Parent")
    assert_equal user.id, new_member.user_id
    assert cookies[:active_family_member_id].present?
  end

  test "create with valid join code when already a member selects existing profile" do
    user = User.create!(email: "existing_member@example.com", password: "password123")
    member = family_members(:one)
    member.update!(user: user)

    post session_path, params: { email: user.email, password: "password123" }

    post join_path, params: { join_code: member.household.join_code }

    assert_redirected_to root_url
    assert_equal "You are already part of #{member.household.name}!", flash[:notice]
  end
end
