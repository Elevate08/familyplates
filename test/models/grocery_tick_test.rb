require "test_helper"

class GroceryTickTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
    @from = Date.new(2026, 10, 12)
    @to = Date.new(2026, 10, 18)
  end

  def record(checked:, at:, key: "produce_carrots_lb", member: nil, to: @to)
    GroceryTick.record!(household: @household, from: @from, to: to, item_key: key,
                        checked: checked, changed_at: at, family_member: member)
  end

  def build(**overrides)
    GroceryTick.new({ household: @household, list_from: @from, list_to: @to, item_key: "a",
                      checked: true, changed_at: Time.current }.merge(overrides))
  end

  # @card-62.10
  test "records a tick for a list" do
    tick = record(checked: true, at: 1.minute.ago)

    assert tick.persisted?
    assert_equal({ "produce_carrots_lb" => true }, @household.grocery_ticks.for_list(@from, @to).checked_map)
  end

  # @card-62.10
  test "one row per household, list and item" do
    record(checked: true, at: 2.minutes.ago)
    record(checked: false, at: 1.minute.ago)

    assert_equal 1, @household.grocery_ticks.count
    assert_not @household.grocery_ticks.first.checked

    duplicate = build(item_key: "produce_carrots_lb")
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  # @card-62.10
  test "the same item on another range is a different tick" do
    record(checked: true, at: 1.minute.ago)
    record(checked: false, at: 1.minute.ago, to: @to + 1.day)

    assert_equal 2, @household.grocery_ticks.count
    assert_equal({ "produce_carrots_lb" => true }, @household.grocery_ticks.for_list(@from, @to).checked_map)
  end

  # @card-62.10
  test "the newest change wins" do
    record(checked: true, at: 1.minute.ago)

    assert_equal true, record(checked: false, at: 5.minutes.ago).reload.checked

    assert_equal false, record(checked: false, at: Time.current - 1.second).reload.checked
  end

  # @card-62.10
  test "an equal timestamp does not overwrite" do
    at = 1.minute.ago.change(usec: 0)
    record(checked: true, at: at)
    assert_equal true, record(checked: false, at: at).reload.checked
  end

  # @card-62.10
  test "a change dated in the future is clamped to now" do
    freeze_time do
      tick = record(checked: true, at: 3.days.from_now)
      assert_equal Time.current, tick.changed_at
    end
  end

  # @card-62.10
  test "records who ticked it, and forgets them if the profile goes" do
    member = family_members(:one)
    tick = record(checked: true, at: 1.minute.ago, member: member)
    assert_equal member, tick.family_member

    member.destroy!
    assert_nil tick.reload.family_member_id
  end

  # @card-62.10
  test "validates the item key" do
    [ "", "Carrots", "a b", "a/b", "x" * 201, "ünï" ].each do |bad|
      tick = build(item_key: bad)
      assert_not tick.valid?, "#{bad.inspect} should be invalid"
      assert tick.errors[:item_key].any?
    end
    assert build(item_key: "a-b_c9").valid?
  end

  # @card-62.10
  test "validates the range" do
    assert_not build(list_from: @to, list_to: @from).valid?
    assert_not build(list_to: @from + GroceryRange::MAX_DAYS.days).valid?
    assert build(list_to: @from + (GroceryRange::MAX_DAYS - 1).days).valid?
  end

  # @card-62.10
  test "a household's ticks go with it" do
    record(checked: true, at: 1.minute.ago)
    other = households(:two)
    GroceryTick.record!(household: other, from: @from, to: @to, item_key: "a", checked: true,
                        changed_at: 1.minute.ago, family_member: nil)

    @household.destroy!

    assert_equal 0, GroceryTick.where(household_id: @household.id).count
    assert_equal 1, other.grocery_ticks.count
  end
end
