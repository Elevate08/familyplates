require "test_helper"

class FamilyMemberTest < ActiveSupport::TestCase
  test "assigns a UUID when created" do
    member = FamilyMember.create!(household: households(:one), name: "New Member")

    assert_match(/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/, member.id)
  end

  test "validates name presence" do
    member = FamilyMember.new(household: households(:one), name: "")
    assert_not member.valid?
    assert_includes member.errors[:name], "can't be blank"
  end

  test "may belong to a user once per household" do
    user = User.create!(email: "parent@example.com")
    first = family_members(:one)
    first.update!(user: user)
    duplicate = FamilyMember.new(household: first.household, user: user, name: "Duplicate")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "has already been taken"
  end

  test "generates signed transfer token and finds member" do
    member = family_members(:two)
    token = member.transfer_id

    assert_equal member, FamilyMember.find_by_transfer_id(token)
  end

  test "transfer_to! reassigns profile to another user" do
    user = User.create!(email: "newuser@example.com")
    member = family_members(:two)

    member.transfer_to!(user)
    assert_equal user.id, member.reload.user_id
  end

  test "calculates initial" do
    member = family_members(:one)
    assert_equal "D", member.initial
  end

  test "clears pin for non-admin members" do
    member = family_members(:two) # role: member
    member.pin = "1234"
    member.valid?
    assert_nil member.pin_digest, "a member profile must not carry a PIN at all"
    assert_not member.requires_pin?
  end

  test "allows pin for admin members" do
    member = family_members(:one) # role: admin
    member.pin = "5678"
    assert member.valid?
    assert member.requires_pin?
    assert member.verify_pin("5678")
    assert_not member.verify_pin("9999")
  end

  test "requires pin for admin members" do
    member = FamilyMember.new(household: households(:one), name: "Admin Person", role: "admin", pin: nil)
    assert_not member.valid?
    assert_includes member.errors[:pin], "can't be blank"

    member.pin = "1234"
    assert member.valid?
    assert member.requires_pin?
  end

  test "validates pin format" do
    member = family_members(:one)
    member.pin = "12"
    assert_not member.valid?
    assert_includes member.errors[:pin], "must be exactly 4 digits"
  end

  test "verify_pin matches only the exact PIN and never raises" do
    admin = family_members(:one)

    assert admin.verify_pin("1234")
    assert admin.verify_pin(" 1234 "), "surrounding whitespace is stripped"
    assert admin.verify_pin(1234), "a non-string is coerced, not blown up"

    # Shorter, longer and empty inputs must return false rather than raise.
    assert_not admin.verify_pin("123")
    assert_not admin.verify_pin("12345")
    assert_not admin.verify_pin("9999")
    assert_not admin.verify_pin("")
    assert_not admin.verify_pin(nil)
  end

  test "verify_pin is false for a member that has no PIN" do
    member = family_members(:two)
    assert_nil member.pin_digest

    assert_not member.verify_pin("1234")
    assert_not member.verify_pin("")
    assert_not member.verify_pin(nil)
  end

  test "a saved PIN cannot be read back off the record" do
    admin = family_members(:one)
    admin.update!(pin: "8642")

    assert admin.verify_pin("8642")

    # reload keeps the in-memory ivar has_secure_password sets, same as
    # ActiveModel's password does, so read the record fresh - that is what any
    # other request, a database copy, or a page rendering the model would see.
    fresh = FamilyMember.find(admin.id)
    assert_nil fresh.pin, "a loaded record must not expose the PIN"
    assert fresh.verify_pin("8642"), "but it must still verify"
    assert_not_includes fresh.pin_digest, "8642"
    assert_not_equal "8642", fresh.pin_digest
  end

  test "a blank PIN submission leaves the existing PIN alone" do
    admin = family_members(:one)

    assert admin.update(pin: "")

    assert admin.reload.verify_pin("1234"), "an untouched form field must not clear the PIN"
  end

  test "promoting a member to admin requires setting a PIN" do
    member = family_members(:two)
    member.role = "admin"

    assert_not member.valid?
    assert_includes member.errors[:pin], "can't be blank"

    member.pin = "4321"
    assert member.valid?
  end
end
