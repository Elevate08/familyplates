require "test_helper"

class UserTest < ActiveSupport::TestCase
  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/

  test "assigns a UUID and normalizes email when created" do
    user = User.create!(email: "  Parent@Example.COM ")

    assert_match UUID_PATTERN, user.id
    assert_equal "parent@example.com", user.email
    assert_nil user.password_digest
  end

  test "email is unique regardless of case" do
    User.create!(email: "parent@example.com")
    duplicate = User.new(email: "PARENT@example.com")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], "has already been taken"
  end

  test "destroying a user removes credentials and sessions but preserves the family profile" do
    user = User.create!(email: "parent@example.com")
    identity = user.identities.create!(provider: "email", uid: user.email)
    session = user.sessions.create!(token: "session-token", last_active_at: Time.current)
    member = family_members(:two)
    member.update!(user: user)

    user.destroy!

    assert_not Identity.exists?(identity.id)
    assert_not Session.exists?(session.id)
    assert_nil member.reload.user_id
  end

  test "supports an optional password for appliance mode while leaving hosted users passwordless" do
    appliance_user = User.create!(email: "appliance@example.com", password: "appliance-password")
    assert appliance_user.authenticate("appliance-password")
    assert_not appliance_user.authenticate("wrong-password")

    hosted_user = User.create!(email: "hosted@example.com")
    assert_nil hosted_user.password_digest
    assert_not hosted_user.authenticate("appliance-password")
  end

  test "resolves reachable households through family profiles" do
    user = User.create!(email: "parent@example.com")
    member = family_members(:one)
    member.update!(user: user)

    assert_equal [ households(:one) ], user.households
  end
end
