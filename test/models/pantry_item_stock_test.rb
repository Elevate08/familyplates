require "test_helper"

class PantryItemStockTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
    @salt = @household.pantry_items.create!(name: "Salt", aisle_category: "Spices & Baking", is_staple: true)
  end

  test "a new item starts stocked" do
    assert_not_predicate @salt, :low_stock?
    assert_predicate @salt, :shielding?
  end

  test "marking low records when, and stops the staple shielding itself" do
    freeze_time do
      @salt.mark_low!

      assert_predicate @salt, :low_stock?
      assert_equal Time.current, @salt.low_stock_at
      assert_not_predicate @salt, :shielding?, "a staple that ran out is not on hand"
      assert_predicate @salt, :is_staple?, "but it is still a staple"
    end
  end

  test "restocking clears the flag and the shield comes back" do
    @salt.mark_low!
    @salt.mark_restocked!

    assert_not_predicate @salt, :low_stock?
    assert_nil @salt.low_stock_at
    assert_predicate @salt, :shielding?
  end

  # The grocery checkbox drives these, and a checkbox is ticked twice as easily
  # as once - from two devices, or through a retry.
  test "both marks are idempotent" do
    original = travel_to(2.hours.ago) { @salt.mark_low!.low_stock_at }

    @salt.mark_low!
    assert_equal original, @salt.reload.low_stock_at, "re-marking must not move the timestamp"

    @salt.mark_restocked!
    @salt.mark_restocked!
    assert_not_predicate @salt.reload, :low_stock?
  end

  test "toggling flips between the two" do
    @salt.toggle_low!
    assert_predicate @salt, :low_stock?

    @salt.toggle_low!
    assert_not_predicate @salt, :low_stock?
  end

  test "scopes separate what is shielding from what needs buying" do
    flour = @household.pantry_items.create!(name: "Flour", aisle_category: "Spices & Baking", is_staple: true)
    sprinkles = @household.pantry_items.create!(name: "Sprinkles", aisle_category: "Spices & Baking", is_staple: false)
    flour.mark_low!

    assert_equal [ flour ], @household.pantry_items.low_stock.to_a
    assert_includes @household.pantry_items.shielding, @salt
    assert_not_includes @household.pantry_items.shielding, flour
    assert_not_includes @household.pantry_items.shielding, sprinkles
  end

  # --- Matching an ingredient line to a pantry row ------------------------

  test "matches on case and plural, which are noise" do
    assert_equal @salt, PantryItem.matching(@household, "salt")
    assert_equal @salt, PantryItem.matching(@household, "  SALTS ")
  end

  test "never matches on a substring, in either direction" do
    butter = @household.pantry_items.create!(name: "Butter", aisle_category: "Dairy & Refrigerated")

    assert_nil PantryItem.matching(@household, "Peanut butter"),
               "a false match is discovered at dinner, when the thing was never bought"
    assert_nil PantryItem.matching(@household, "Butternut squash")
    assert_equal butter, PantryItem.matching(@household, "Butter")
  end

  test "matches nothing across households, or for nothing" do
    assert_nil PantryItem.matching(households(:two), "Salt")
    assert_nil PantryItem.matching(@household, "")
    assert_nil PantryItem.matching(nil, "Salt")
  end
end
