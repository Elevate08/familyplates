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
end
