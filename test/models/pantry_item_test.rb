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

  test "emoji_for matches expected emojis with correct precedence" do
    assert_equal "🥛", PantryItem.emoji_for("sour cream")
    assert_equal "🥛", PantryItem.emoji_for("milk")
    assert_equal "🥛", PantryItem.emoji_for("heavy cream")

    assert_equal "🫙", PantryItem.emoji_for("garlic powder")
    assert_equal "🧄", PantryItem.emoji_for("garlic")

    assert_equal "🫙", PantryItem.emoji_for("onion powder")
    assert_equal "🧅", PantryItem.emoji_for("yellow onion")

    assert_equal "🌻", PantryItem.emoji_for("canola oil")
    assert_equal "🌻", PantryItem.emoji_for("vegetable oil")
    assert_equal "🍾", PantryItem.emoji_for("olive oil")
    assert_equal "🍾", PantryItem.emoji_for("cooking oil")

    assert_equal "🥬", PantryItem.emoji_for("unknown vegetable", "Produce")
    assert_equal "📦", PantryItem.emoji_for("unknown item", "Other")
  end
end
