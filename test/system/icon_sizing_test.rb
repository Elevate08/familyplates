require "application_system_test_case"

# Icon sizing was wrong in a way no class assertion would have caught on its
# own: pantry_icon_tag ignored css_class on the emoji path, so a pantry item
# with an emoji rendered at whatever size it inherited while a hand-drawn SVG
# in the same list took the size the page asked for. This measures what the
# browser actually laid out.
class IconSizingTest < ApplicationSystemTestCase
  setup do
    @household = households(:one)
    sign_in_as(family_members(:one))
  end

  test "an emoji ingredient icon matches an svg one in the same list" do
    recipe = @household.recipes.create!(title: "Mixed Icons", instructions: "x")
    # "black pepper" matches a hand-drawn SVG; "banana" falls through to emoji.
    recipe.recipe_ingredients.create!(name: "black pepper", aisle_category: "Spices & Baking")
    recipe.recipe_ingredients.create!(name: "banana", aisle_category: "Produce")

    visit recipe_path(recipe)
    assert_selector "h1", wait: 5

    boxes = visible_icon_boxes

    svgs = boxes.select { |b| b["tag"] == "svg" }
    spans = boxes.select { |b| b["tag"] == "SPAN" }

    assert_operator svgs.length, :>=, 1, "precondition: the page draws at least one svg icon"
    assert_operator spans.length, :>=, 1, "precondition: the page draws at least one emoji icon"

    sizes = boxes.map { |b| [ b["width"], b["height"] ] }.uniq
    assert_equal 1, sizes.length,
      "icons in one list rendered at different sizes: #{boxes.inspect}"
  end

  private

  # Scoped to the ingredient list itself - each row wraps its icon in a fixed
  # w-6 h-6 box - so an icon elsewhere on the page at a different size is not
  # mistaken for the inconsistency being tested. Zero-sized nodes live in
  # collapsed sections and are not what a reader sees, so they are left out.
  def visible_icon_boxes
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("ul li div.w-6.h-6 > svg, ul li div.w-6.h-6 > span"))
        .map((el) => {
          const r = el.getBoundingClientRect();
          return { tag: el.tagName, width: Math.round(r.width), height: Math.round(r.height) };
        })
        .filter((b) => b.width > 0 && b.height > 0)
    JS
  end
end
