require "test_helper"

class UserIdentityLinkingTest < ActiveSupport::TestCase
  test "creates new user and links identity when account does not exist" do
    assert_difference -> { User.count } => 1, -> { Identity.count } => 1 do
      user = User.find_or_create_from_identity(
        provider: "google",
        uid: "google-uid-1",
        email: "newchef@example.com",
        name: "New Chef"
      )

      assert_equal "newchef@example.com", user.email
      assert user.identities.exists?(provider: "google", uid: "google-uid-1")
    end
  end

  test "links identity to existing user without creating duplicate user" do
    existing_user = User.create!(email: "existing@example.com", password: "password123")

    assert_no_difference -> { User.count } do
      assert_difference -> { Identity.count } => 1 do
        user = User.find_or_create_from_identity(
          provider: "apple",
          uid: "apple-sub-1",
          email: "Existing@Example.com"
        )

        assert_equal existing_user.id, user.id
        assert existing_user.identities.exists?(provider: "apple", uid: "apple-sub-1")
      end
    end
  end

  test "returns existing user when identity is already linked" do
    user = User.create!(email: "member@example.com")
    identity = user.identities.create!(provider: "oidc", uid: "oidc-sub-1")

    assert_no_difference -> { User.count } do
      assert_no_difference -> { Identity.count } do
        found_user = User.find_or_create_from_identity(
          provider: "oidc",
          uid: "oidc-sub-1",
          email: "member@example.com"
        )

        assert_equal user.id, found_user.id
      end
    end
  end

  test "raises error when creating brand new user with blank email" do
    assert_raises(ActiveRecord::RecordInvalid) do
      User.find_or_create_from_identity(
        provider: "oidc",
        uid: "sub-without-email",
        email: ""
      )
    end
  end

  test "can_disconnect_identity? requires at least one other credential" do
    user = User.create!(email: "user@example.com")
    identity1 = user.identities.create!(provider: "google", uid: "uid-1")

    # Only 1 identity, no password, no passkey => cannot disconnect
    assert_not user.can_disconnect_identity?(identity1)

    # Adding a password allows disconnecting
    user.update!(password: "new-password123")
    assert user.can_disconnect_identity?(identity1)

    # Removing password but adding a second identity allows disconnecting
    user.update_column(:password_digest, nil)
    identity2 = user.identities.create!(provider: "apple", uid: "uid-2")
    assert user.can_disconnect_identity?(identity1)
    assert user.can_disconnect_identity?(identity2)

    # Cannot disconnect an identity belonging to another user
    other_user = User.create!(email: "other@example.com")
    other_identity = other_user.identities.create!(provider: "google", uid: "uid-other")
    assert_not user.can_disconnect_identity?(other_identity)
  end
end
