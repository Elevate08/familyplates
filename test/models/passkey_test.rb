require "test_helper"

class PasskeyTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "passkey_user@example.com", password: "password123")
  end

  test "validates required attributes and uniqueness" do
    passkey = @user.passkeys.build(
      external_id: "ext-123",
      public_key: "pub-key-data",
      sign_count: 0
    )
    assert passkey.valid?

    passkey.save!

    duplicate = @user.passkeys.build(
      external_id: "ext-123",
      public_key: "pub-key-other",
      sign_count: 0
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:external_id], "has already been taken"
  end

  test "syncs Identity on create and cleans up on destroy" do
    assert_difference -> { Identity.where(provider: "passkey").count } => 1 do
      @passkey = @user.passkeys.create!(
        external_id: "cred-abc-1",
        public_key: "dummy-key",
        nickname: "MacBook Touch ID"
      )
    end

    identity = @user.identities.find_by(provider: "passkey", uid: "cred-abc-1")
    assert identity.present?

    assert_difference -> { Identity.where(provider: "passkey").count } => -1 do
      @passkey.destroy
    end
  end

  test "label returns nickname or formatted date" do
    named_passkey = @user.passkeys.create!(
      external_id: "cred-1",
      public_key: "dummy",
      nickname: "YubiKey 5C"
    )
    assert_equal "YubiKey 5C", named_passkey.label

    unnamed_passkey = @user.passkeys.create!(
      external_id: "cred-2",
      public_key: "dummy"
    )
    assert_includes unnamed_passkey.label, "Passkey ("
  end

  test "update_sign_count! updates count and last_used_at" do
    passkey = @user.passkeys.create!(
      external_id: "cred-count",
      public_key: "dummy",
      sign_count: 5
    )

    passkey.update_sign_count!(10)
    assert_equal 10, passkey.reload.sign_count
    assert passkey.last_used_at.present?
  end
end
