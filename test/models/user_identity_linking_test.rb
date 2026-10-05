require "test_helper"

class UserIdentityLinkingTest < ActiveSupport::TestCase
  # @card-20.3
  test "creates new user and links identity when account does not exist" do
    assert_difference -> { User.count } => 1, -> { Identity.count } => 1 do
      user = User.find_or_create_from_identity(
        provider: "google",
        uid: "google-uid-1",
        email: "newchef@example.com",
        email_verified: true,
        name: "New Chef"
      )

      assert_equal "newchef@example.com", user.email
      assert user.identities.exists?(provider: "google", uid: "google-uid-1")
    end
  end

  # @card-20.2
  test "links identity to existing user without creating duplicate user" do
    existing_user = User.create!(email: "existing@example.com", password: "password123")

    assert_no_difference -> { User.count } do
      assert_difference -> { Identity.count } => 1 do
        user = User.find_or_create_from_identity(
          provider: "google",
          uid: "google-sub-1",
          email: "Existing@Example.com",
          email_verified: "true"
        )

        assert_equal existing_user.id, user.id
        assert existing_user.identities.exists?(provider: "google", uid: "google-sub-1")
      end
    end
  end

  test "does not link identity to existing user when email is unverified or flag omitted" do
    User.create!(email: "victim@example.com", password: "password123")

    [ { email_verified: false }, { email_verified: "false" }, {} ].each do |extra|
      assert_no_difference [ "User.count", "Identity.count" ] do
        assert_raises(ActiveRecord::RecordInvalid) do
          User.find_or_create_from_identity(provider: "oidc", uid: "attacker-uid", email: "victim@example.com", **extra)
        end
      end
    end
  end

  test "does not create new user when email is unverified" do
    assert_no_difference [ "User.count", "Identity.count" ] do
      assert_raises(ActiveRecord::RecordInvalid) do
        User.find_or_create_from_identity(provider: "google", uid: "g-1", email: "fresh@example.com", email_verified: false)
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

  # @card-20.5
  test "can_disconnect_identity? requires at least one other credential" do
    enable_google_and_oidc!
    user = User.create!(email: "user@example.com")
    identity1 = user.identities.create!(provider: "google", uid: "uid-1")

    # Only 1 identity, no password, no passkey => cannot disconnect
    assert_not user.can_disconnect_identity?(identity1)

    # Adding a password allows disconnecting
    user.update!(password: "new-password123")
    assert user.can_disconnect_identity?(identity1)

    # Removing password but adding a second identity allows disconnecting
    user.update_column(:password_digest, nil)
    identity2 = user.identities.create!(provider: "oidc", uid: "uid-2")
    assert user.can_disconnect_identity?(identity1)
    assert user.can_disconnect_identity?(identity2)

    # Cannot disconnect an identity belonging to another user
    other_user = User.create!(email: "other@example.com")
    other_identity = other_user.identities.create!(provider: "google", uid: "uid-other")
    assert_not user.can_disconnect_identity?(other_identity)
  ensure
    FamilyPlates.config.reset!
  end

  # Apple sign-in is removed, and a provider can be switched off: an identity
  # nobody can sign in with is not a way back into the account.
  test "an identity for a provider that cannot sign in does not count as another way in" do
    enable_google_and_oidc!
    user = User.create!(email: "apple-left@example.com")
    google = user.identities.create!(provider: "google", uid: "g-left")
    user.identities.create!(provider: "apple", uid: "apple-left")
    assert_not user.can_disconnect_identity?(google)

    oidc = user.identities.create!(provider: "oidc", uid: "o-left")
    assert user.can_disconnect_identity?(google)

    FamilyPlates.config.oidc_auth_enabled = false
    assert_not user.can_disconnect_identity?(google), "OIDC is switched off, so only Google still signs in"
    assert user.can_disconnect_identity?(oidc), "an unusable identity can always be removed while Google remains"
  ensure
    FamilyPlates.config.reset!
  end

  private

  def enable_google_and_oidc!
    config = FamilyPlates.config
    config.google_auth_enabled = true
    config.google_client_id = "google-client"
    config.google_client_secret = "google-secret"
    config.oidc_auth_enabled = true
    config.oidc_client_id = "oidc-client"
    config.oidc_client_secret = "oidc-secret"
    config.oidc_issuer = "https://auth.example.com"
  end
end
