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
end
