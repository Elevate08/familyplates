require "test_helper"

class FamilyMemberTest < ActiveSupport::TestCase
  test "validates name presence" do
    member = FamilyMember.new(household: households(:one), name: "")
    assert_not member.valid?
    assert_includes member.errors[:name], "can't be blank"
  end

  test "calculates initial" do
    member = family_members(:one)
    assert_equal "D", member.initial
  end

  test "clears pin for non-admin members" do
    member = family_members(:two) # role: member
    member.pin = "1234"
    member.valid?
    assert_nil member.pin
    assert_not member.requires_pin?
  end

  test "allows pin for admin members" do
    member = family_members(:one) # role: admin
    member.pin = "5678"
    assert member.valid?
    assert_equal "5678", member.pin
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
    assert_equal "1234", admin.pin

    assert admin.verify_pin("1234")
    assert admin.verify_pin(" 1234 "), "surrounding whitespace is stripped"
    assert admin.verify_pin(1234), "a non-string is coerced, not blown up"

    # Shorter, longer and empty inputs must return false rather than raise -
    # fixed_length_secure_compare raises on a length mismatch if reached directly.
    assert_not admin.verify_pin("123")
    assert_not admin.verify_pin("12345")
    assert_not admin.verify_pin("9999")
    assert_not admin.verify_pin("")
    assert_not admin.verify_pin(nil)
  end

  test "verify_pin is false for a member that has no PIN" do
    member = family_members(:two)
    assert_nil member.pin

    assert_not member.verify_pin("1234")
    assert_not member.verify_pin("")
    assert_not member.verify_pin(nil)
  end
end
