require "test_helper"

class PantryItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = family_members(:one)
    @item = pantry_items(:one)
    sign_in_as(@admin)
  end

  test "should get index" do
    get pantry_items_url
    assert_response :success
  end

  test "should create pantry item" do
    assert_difference("PantryItem.count", 1) do
      post pantry_items_url, params: {
        pantry_item: { name: "Honey", aisle_category: "Pantry & Grains", is_staple: true }
      }
    end
    assert_redirected_to pantry_items_url
  end

  test "should create pantry item with custom icon" do
    assert_difference("PantryItem.count", 1) do
      post pantry_items_url, params: {
        pantry_item: { name: "Tellicherry Black Pepper", aisle_category: "Spices & Baking", emoji: "pepper-shaker", is_staple: true }
      }
    end
    assert_redirected_to pantry_items_url
    assert_equal "pepper-shaker", PantryItem.last.emoji
  end

  test "should toggle staple" do
    patch toggle_staple_pantry_item_url(@item)
    assert_redirected_to pantry_items_url
    assert_not @item.reload.is_staple?
  end

  test "should destroy pantry item" do
    assert_difference("PantryItem.count", -1) do
      delete pantry_item_url(@item)
    end
    assert_redirected_to pantry_items_url
  end

  # --- Invalid submissions ----------------------------------------------------
  #
  # The pantry form is Turbo-driven, and Rails does not fall back to HTML for a
  # turbo_stream request. There is no index.turbo_stream.erb, so every invalid
  # submission raised MissingTemplate and returned a 500 instead of showing the
  # validation error.

  TURBO_HEADERS = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }.freeze

  test "a blank name over turbo_stream shows the error instead of a 500" do
    assert_no_difference "PantryItem.count" do
      post pantry_items_url, params: { pantry_item: { name: "" } }, headers: TURBO_HEADERS
    end

    assert_response :unprocessable_entity
    assert_match(/can&#39;t be blank|can't be blank/, response.body)
  end

  test "a duplicate name over turbo_stream shows the error instead of a 500" do
    assert_no_difference "PantryItem.count" do
      post pantry_items_url, params: { pantry_item: { name: @item.name, aisle_category: "Other" } }, headers: TURBO_HEADERS
    end

    assert_response :unprocessable_entity
  end

  test "a blank name over plain HTML also re-renders the form" do
    post pantry_items_url, params: { pantry_item: { name: "" } }

    assert_response :unprocessable_entity
    assert_select "form"
  end

  test "an invalid update over turbo_stream shows the error instead of a 500" do
    patch pantry_item_url(@item), params: { pantry_item: { name: "" } }, headers: TURBO_HEADERS

    assert_response :unprocessable_entity
    assert_equal @item.name, @item.reload.name
  end
end
