require "test_helper"

class GroceryTicksControllerTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @admin = family_members(:one)
    @member = family_members(:two)
    @from = @household.today.beginning_of_week
    @to = @from + 6.days
    sign_in_as(@admin)
  end

  def tick_params(overrides = {})
    { from: @from.iso8601, to: @to.iso8601, item_key: "produce_carrots_lb", checked: true,
      changed_at: Time.current.iso8601(3) }.merge(overrides)
  end

  def put_tick(overrides = {})
    put grocery_ticks_url, params: tick_params(overrides), as: :json
  end

  def json = response.parsed_body

  # @card-62.10
  test "an organizer sets a tick and any member can read it back" do
    put_tick
    assert_response :success
    assert_equal true, @household.grocery_ticks.find_by!(item_key: "produce_carrots_lb").checked
    assert_equal @admin, @household.grocery_ticks.first.family_member

    sign_in_as(@member)
    get grocery_ticks_url, params: { from: @from.iso8601, to: @to.iso8601 }, as: :json
    assert_response :success
    assert_equal({ "produce_carrots_lb" => true }, json["ticks"])
  end

  # @card-62.10
  test "reading only returns the asked-for list" do
    put_tick
    put_tick(to: (@to + 1.day).iso8601, item_key: "dairy_milk_l")

    get grocery_ticks_url, params: { from: @from.iso8601, to: @to.iso8601 }, as: :json
    assert_equal [ "produce_carrots_lb" ], json["ticks"].keys
  end

  # @card-62.10
  test "an older change does not overwrite a newer one, and says what stands" do
    put_tick(checked: true, changed_at: 1.minute.ago.iso8601(3))
    put_tick(checked: false, changed_at: 5.minutes.ago.iso8601(3))

    assert_response :success
    assert_equal true, json["checked"]
    assert_equal true, @household.grocery_ticks.first.checked
  end

  # @card-62.10
  test "a future timestamp is clamped" do
    put_tick(changed_at: 2.days.from_now.iso8601)
    assert_operator @household.grocery_ticks.first.changed_at, :<=, Time.current
  end

  # @card-62.11
  test "a tick is saved once even if the same change is sent twice" do
    at = 1.minute.ago.iso8601(3)
    2.times { put_tick(changed_at: at) }
    assert_response :success
    assert_equal 1, @household.grocery_ticks.count
  end

  # @card-62.12
  test "reset clears the list's ticks for everyone, and only that list" do
    put_tick
    put_tick(item_key: "dairy_milk_l")
    put_tick(to: (@to + 1.day).iso8601)

    delete grocery_ticks_url, params: { from: @from.iso8601, to: @to.iso8601 }, as: :json
    assert_response :success

    assert_equal 0, @household.grocery_ticks.where(list_from: @from, list_to: @to).count
    assert_equal 1, @household.grocery_ticks.count
  end

  # @card-62.13
  test "an ordinary member cannot tick or reset, but can read" do
    put_tick
    sign_in_as(@member)

    put_tick(item_key: "dairy_milk_l", checked: true)
    assert_response :forbidden
    delete grocery_ticks_url, params: { from: @from.iso8601, to: @to.iso8601 }, as: :json
    assert_response :forbidden

    assert_equal [ "produce_carrots_lb" ], @household.grocery_ticks.pluck(:item_key)
    get grocery_ticks_url, params: { from: @from.iso8601, to: @to.iso8601 }, as: :json
    assert_response :success
  end

  # @card-62.10
  test "rejects a bad item key" do
    [ "Carrots", "a b", "x" * 201, "" ].each do |bad|
      put_tick(item_key: bad)
      assert_response :unprocessable_entity, "#{bad.inspect}"
    end
    assert_equal 0, @household.grocery_ticks.count
  end

  # @card-62.10
  test "rejects bad dates, backwards ranges and over-long ranges" do
    put_tick(from: "nonsense")
    assert_response :unprocessable_entity
    put_tick(from: @to.iso8601, to: @from.iso8601)
    assert_response :unprocessable_entity
    put_tick(to: (@from + GroceryRange::MAX_DAYS.days).iso8601)
    assert_response :unprocessable_entity
    put_tick(changed_at: "not a time")
    assert_response :unprocessable_entity

    get grocery_ticks_url, params: { from: "x", to: "y" }, as: :json
    assert_response :unprocessable_entity
    delete grocery_ticks_url, params: { from: @to.iso8601, to: @from.iso8601 }, as: :json
    assert_response :unprocessable_entity

    assert_equal 0, @household.grocery_ticks.count
  end

  # @card-62.10
  test "a missing checked flag is rejected rather than read as false" do
    put grocery_ticks_url, params: tick_params.except(:checked), as: :json
    assert_response :unprocessable_entity
  end

  # @card-62.10
  test "the grocery page shows a stored tick as checked, and an un-ticked staple as unchecked" do
    get grocery_list_url(from: @from.iso8601, to: @to.iso8601)
    boxes = css_select("input[type=checkbox][data-checklist-target=checkbox]")
    assert boxes.any?
    unchecked = boxes.reject { |box| box["checked"] }
    staple = boxes.find { |box| box["checked"] }
    target = unchecked.first["value"]

    put_tick(item_key: target)
    put_tick(item_key: staple["value"], checked: false) if staple

    get grocery_list_url(from: @from.iso8601, to: @to.iso8601)
    assert_select "input[type=checkbox][value='#{target}'][checked]", 1
    assert_select "input[type=checkbox][value='#{staple['value']}'][checked]", 0 if staple
    assert_select "[data-checklist-ticks-url-value]", 1
  end

  # @card-62.10
  test "a tick for another range does not show on this page" do
    get grocery_list_url(from: @from.iso8601, to: @to.iso8601)
    target = css_select("input[type=checkbox][data-checklist-target=checkbox]").reject { |b| b["checked"] }.first["value"]

    put_tick(item_key: target, to: (@to + 1.day).iso8601)

    get grocery_list_url(from: @from.iso8601, to: @to.iso8601)
    assert_select "input[type=checkbox][value='#{target}'][checked]", 0
  end

  # @card-62.10
  test "the tick endpoints are never cached by the browser" do
    get grocery_ticks_url, params: { from: @from.iso8601, to: @to.iso8601 }, as: :json
    assert_match(/no-store|private/, response.headers["Cache-Control"].to_s)
  end
end
