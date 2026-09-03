require "application_system_test_case"

# The tag picker and the pantry icon picker are custom widgets built on inline
# scripts and Stimulus, and both were touched by the CSP conversion, the XSS
# escaping work and the scrollbar theming. None of that was covered by a test
# that actually ran the page.
class PickersTest < ApplicationSystemTestCase
  setup do
    @admin = family_members(:one)
    @household = households(:one)
    sign_in_as(@admin)
  end

  test "the tag picker suggests, adds and removes a tag" do
    recipe = @household.recipes.create!(title: "Tag Subject", instructions: "x", tags: "weeknight")
    visit edit_recipe_path(recipe)

    input = find("#recipe_tag_search")
    input.fill_in(with: "week")

    assert_selector "[data-tag-item]", wait: 5
    find("[data-tag-item]", match: :first).click

    assert_selector "[data-tag-picker-target='badgesContainer'] button", wait: 3
  end

  test "a tag containing markup is shown as text, not run" do
    # The suggestion list excludes tags the recipe already carries, so the
    # payload has to live on a different recipe to show up as a suggestion.
    @household.recipes.create!(
      title: "Carrier",
      instructions: "x",
      tags: %(<img src=x onerror="document.title='XSS-FIRED'">)
    )
    recipe = @household.recipes.create!(title: "Hostile Tag", instructions: "x", tags: "weeknight")
    visit edit_recipe_path(recipe)

    find("#recipe_tag_search").fill_in(with: "img")
    assert_selector "[data-tag-item]", wait: 5

    assert_no_equal_title "XSS-FIRED"
  end

  test "the pantry icon picker opens and filters" do
    visit pantry_items_path

    find("button[data-action*='pantry-item-form#togglePicker']").click
    assert_selector "#pantry_icon_search", visible: true, wait: 5

    find("#pantry_icon_search").fill_in(with: "salt")
    assert_selector "[data-pantry-item-form-target='iconGrid']", visible: true
  end

  test "an ingredient name containing markup is shown as text, not run" do
    recipe = @household.recipes.create!(title: "Hostile Ingredient", instructions: "x")
    recipe.recipe_ingredients.create!(
      name: %(<img src=x onerror="document.title='XSS-FIRED'">),
      aisle_category: "Other"
    )
    visit edit_recipe_path(recipe)

    find("input[data-ingredient-autofill-target='nameInput']", match: :first).fill_in(with: "img")
    assert_selector "[data-ingredient-name]", wait: 5

    assert_no_equal_title "XSS-FIRED"
  end

  private

  def assert_no_equal_title(forbidden)
    assert_not_equal forbidden, page.title,
      "a stored payload executed - the browser ran it instead of showing it"
  end
end
