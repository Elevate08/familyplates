require "test_helper"

class PantryItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @item = pantry_items(:one)
    sign_in_as(@user)
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
end
