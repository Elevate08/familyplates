require "test_helper"

class IdentityTest < ActiveSupport::TestCase
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  test "assigns a UUID and identifies a provider account once" do
    user = User.create!(email: "parent@example.com")
    identity = user.identities.create!(provider: "oidc", uid: "provider-account")
    duplicate = user.identities.build(provider: "oidc", uid: "provider-account")

    assert_match UUID_PATTERN, identity.id
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:uid], "has already been taken"
  end
end
