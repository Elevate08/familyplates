require "test_helper"

class PantryItemTest < ActiveSupport::TestCase
  test "validates presence of name" do
    item = PantryItem.new(household: households(:one), name: "")
    assert_not item.valid?
    assert_includes item.errors[:name], "can't be blank"
  end

  test "validates uniqueness of name per household" do
    duplicate = PantryItem.new(household: households(:one), name: "Olive Oil", aisle_category: "Pantry & Grains")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "toggle_staple! switches status" do
    item = pantry_items(:one)
    assert item.is_staple?
    item.toggle_staple!
    assert_not item.reload.is_staple?
  end
end
