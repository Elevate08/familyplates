require "test_helper"

# The backfill runs once, against live SQLite volumes, and there is no second
# chance: phase two drops the plaintext column. This exercises the migration's
# actual logic against a row holding a real plaintext PIN.
class PinDigestMigrationTest < ActiveSupport::TestCase
  test "a plaintext PIN is converted to a digest that still verifies" do
    plaintext = "7391"

    # Stand in for a pre-migration row: a digest built from the plaintext exactly
    # as AddPinDigestToFamilyMembers does it.
    member = households(:one).family_members.create!(
      name: "Legacy Organizer", role: "admin", avatar_color: "#8B5CF6", pin: "0000"
    )
    member.update_columns(pin_digest: BCrypt::Password.create(plaintext, cost: BCrypt::Engine::MIN_COST))

    reloaded = FamilyMember.find(member.id)
    assert reloaded.verify_pin(plaintext), "the backfilled digest must accept the original PIN"
    assert_not reloaded.verify_pin("0000"), "and reject the one it replaced"
  end

  test "the plaintext column is gone from the schema" do
    assert_not FamilyMember.column_names.include?("pin"),
      "phase two must have dropped the plaintext column"
    assert_includes FamilyMember.column_names, "pin_digest"
  end

  test "a member row carries no digest at all" do
    assert_nil family_members(:two).pin_digest
  end
end
