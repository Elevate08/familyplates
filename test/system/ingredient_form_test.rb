require "application_system_test_case"

# The ingredient autofill was the single richest source of defects a request test
# could not see: a controller that failed to register, a catalogue read from the
# wrong element, options left in the tab order, Enter creating a near-duplicate
# instead of picking the obvious match. Each test here corresponds to a bug that
# reached a human reviewer.
class IngredientFormTest < ApplicationSystemTestCase
  setup do
    @admin = family_members(:one)
    @household = households(:one)
    @recipe = @household.recipes.create!(title: "Autofill Subject", instructions: "Mix.")
    @recipe.recipe_ingredients.create!(name: "Chicken Breast", aisle_category: "Meat & Seafood")
    @recipe.recipe_ingredients.create!(name: "Olive Oil", aisle_category: "Pantry & Grains")

    sign_in_as(@admin)
    visit edit_recipe_path(@recipe)
  end

  def name_inputs
    all("input[name*='[name]'][data-ingredient-autofill-target='nameInput']")
  end

  def unit_inputs
    all("input[data-ingredient-autofill-target='unitInput']")
  end

  test "typing an ingredient name offers a matching suggestion" do
    name_inputs.first.fill_in(with: "Chick")

    assert_selector "[data-ingredient-name='Chicken Breast']", wait: 3
  end

  test "the suggestion list appears before the add option" do
    name_inputs.first.fill_in(with: "Chick")
    assert_selector "[data-ingredient-name]", wait: 3

    menu = find("[data-ingredient-autofill-target='nameDropdown']", visible: true)
    html = menu["innerHTML"]

    assert_operator html.index("data-ingredient-name"), :<, html.index("handleCreateNameClick"),
      "Add must sit below the matches, or Enter creates a near-duplicate"
  end

  test "Enter takes the matching suggestion rather than creating a shorter name" do
    input = name_inputs.first
    input.fill_in(with: "Chick")
    assert_selector "[data-ingredient-name='Chicken Breast']", wait: 3

    input.send_keys(:enter)

    assert_equal "Chicken Breast", input.value
  end

  test "arrow keys move through the suggestions and Enter takes the highlighted one" do
    input = name_inputs.first
    input.fill_in(with: "o")
    assert_selector "[data-ingredient-name]", wait: 3

    input.send_keys(:arrow_down)
    highlighted = find("[data-highlighted='true']", wait: 3)
    expected = highlighted["data-ingredient-name"]

    input.send_keys(:enter)

    assert_equal expected, input.value
  end

  test "tabbing away closes the menu instead of moving into it" do
    input = name_inputs.first
    input.fill_in(with: "Chick")
    assert_selector "[data-ingredient-autofill-target='nameDropdown']", visible: true, wait: 3

    input.send_keys(:tab)

    assert_no_selector "[data-ingredient-autofill-target='nameDropdown']", visible: true, wait: 3
  end

  test "the measurement field autofills too" do
    unit = unit_inputs.first
    unit.fill_in(with: "cu")

    assert_selector "[data-unit-name]", wait: 3
    unit.send_keys(:arrow_down, :enter)

    assert_not_equal "cu", unit.value, "the highlighted unit should have replaced the query"
  end

  test "a newly added row autofills like the rest" do
    before = name_inputs.length
    click_on "+ Add Ingredient"

    assert_selector "input[data-ingredient-autofill-target='nameInput']", count: before + 1, wait: 3

    name_inputs.last.fill_in(with: "Chick")
    assert_selector "[data-ingredient-name='Chicken Breast']", wait: 3
  end

  test "rows added in quick succession each keep their own name" do
    3.times { click_on "+ Add Ingredient" }

    fresh = name_inputs.last(3)
    fresh.each_with_index { |input, i| input.fill_in(with: "Rapid Ingredient #{i}") }

    click_on "Save Recipe"
    assert_no_current_path edit_recipe_path(@recipe), wait: 5

    saved = @recipe.reload.recipe_ingredients.pluck(:name)
    3.times { |i| assert_includes saved, "Rapid Ingredient #{i}" }
  end
end
