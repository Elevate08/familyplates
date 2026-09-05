require "test_helper"

# The full loop the card describes: a staple runs low, stops shielding itself,
# appears on the grocery list with a Restock badge, and goes back to shielding
# once it has been bought.
class PantryRestockCycleTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @admin = family_members(:one)
    @plan = @household.current_meal_plan

    @recipe = @household.recipes.create!(title: "Buttered Toast", instructions: "1. Toast it.")
    @recipe.recipe_ingredients.create!(name: "Butter", quantity: 2, unit: "tbsp", aisle_category: "Dairy & Refrigerated")
    @recipe.recipe_ingredients.create!(name: "Bread", quantity: 1, aisle_category: "Bakery")

    @plan.meal_plan_slots.destroy_all
    @plan.meal_plan_slots.create!(date: @household.today, meal_type: "breakfast", recipe: @recipe)

    @butter = @household.pantry_items.create!(name: "Butter", aisle_category: "Dairy & Refrigerated", is_staple: true)
    @salt = @household.pantry_items.create!(name: "Salt", aisle_category: "Spices & Baking", is_staple: true)

    sign_in_as(@admin)
  end

  def aggregate
    IngredientAggregator.call(@plan.reload)
  end

  def item_named(name)
    aggregate[:aisles].values.flatten.find { |item| item[:name].casecmp?(name) }
  end

  # --- Suppression and un-suppression -------------------------------------

  test "a stocked staple stays shielded from the shopping count" do
    butter = item_named("Butter")

    assert butter[:is_staple], "on hand"
    assert_not butter[:restock]
    assert_equal 1, aggregate[:total_shopping_count], "only the bread needs buying"
  end

  test "marking a staple low un-suppresses it onto the list as a restock" do
    @butter.mark_low!

    butter = item_named("Butter")
    assert_not butter[:is_staple], "no longer reads as already in the pantry"
    assert butter[:restock]
    assert_equal @butter.id, butter[:pantry_item_id]
    assert_equal 2, aggregate[:total_shopping_count]
    assert_equal 1, aggregate[:total_restock_count]
  end

  # Running low on salt is exactly the case no recipe would ever surface.
  test "a low staple no recipe calls for still lands on the list" do
    assert_nil item_named("Salt")

    @salt.mark_low!

    salt = item_named("Salt")
    assert_not_nil salt, "the whole point of a restock prompt"
    assert salt[:restock]
    assert_nil salt[:quantity], "nothing asked for a quantity of it"
    assert_empty salt[:sources]
  end

  test "restock lines sort above the rest of their aisle" do
    @butter.mark_low!

    dairy = aggregate[:aisles]["Dairy & Refrigerated"]
    assert dairy.first[:restock], "the thing somebody went out of their way to flag comes first"
  end

  test "restocking puts the shield back and the list returns to normal" do
    @butter.mark_low!
    assert_equal 2, aggregate[:total_shopping_count]

    @butter.mark_restocked!

    butter = item_named("Butter")
    assert butter[:is_staple]
    assert_not butter[:restock]
    assert_equal 1, aggregate[:total_shopping_count]
    assert_equal 0, aggregate[:total_restock_count]
  end

  test "a low item that is not a staple changes nothing - it was never shielded" do
    bread = @household.pantry_items.create!(name: "Bread", aisle_category: "Bakery", is_staple: false)
    bread.mark_low!

    item = item_named("Bread")
    assert_not item[:is_staple]
    assert_not item[:restock], "it was already on the list; a badge would be noise"
  end

  # --- The controls -------------------------------------------------------

  test "toggle_low flips the flag and answers with just the row that changed" do
    patch toggle_low_pantry_item_url(@butter), as: :turbo_stream

    assert_response :success
    assert_predicate @butter.reload, :low_stock?
    assert_includes response.body, "turbo-stream"
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(@butter, :stock)

    patch toggle_low_pantry_item_url(@butter), as: :turbo_stream
    assert_not_predicate @butter.reload, :low_stock?
  end

  test "restock and mark_low are idempotent, which is what the checkbox needs" do
    patch restock_pantry_item_url(@butter)
    patch restock_pantry_item_url(@butter)
    assert_not_predicate @butter.reload, :low_stock?

    patch mark_low_pantry_item_url(@butter)
    patch mark_low_pantry_item_url(@butter)
    assert_predicate @butter.reload, :low_stock?
  end

  test "the toggle is offered beside the recipe's ingredients and in cook mode" do
    get recipe_url(@recipe)
    assert_select "form[action=?]", toggle_low_pantry_item_path(@butter)

    get cook_recipe_url(@recipe)
    assert_select "form[action=?]", toggle_low_pantry_item_path(@butter)
  end

  test "an ingredient the pantry does not track gets no toggle" do
    @butter.destroy!

    get recipe_url(@recipe)
    assert_select "[id^='stock_pantry_item']", false
  end

  # --- The grocery list end ----------------------------------------------

  test "the grocery list badges a restock line and wires it back to the pantry" do
    @butter.mark_low!

    get grocery_list_url

    assert_response :success
    assert_includes response.body, "Restock"
    assert_includes response.body, "1 to restock", "the header says how many prompts are waiting"
    assert_select "[data-pantry-item-id=?]", @butter.id.to_s
    assert_select "[data-restock-url=?]", restock_pantry_item_path(@butter)
    assert_select "[data-mark-low-url=?]", mark_low_pantry_item_path(@butter)
  end

  test "an ordinary line carries no pantry wiring" do
    get grocery_list_url

    assert_select "[data-restock-url]", false
  end

  test "another household's pantry cannot be flagged from here" do
    outsider = households(:two).pantry_items.create!(name: "Theirs", aisle_category: "Other", is_staple: true)

    patch toggle_low_pantry_item_url(outsider)

    assert_response :not_found
    assert_not_predicate outsider.reload, :low_stock?
  end
end
