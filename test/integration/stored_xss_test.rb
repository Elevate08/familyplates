require "test_helper"

# Server-rendered counterpart to the DOM-sink work in A6. That task swept
# app/javascript and missed app/helpers entirely: pantry_icon_tag interpolated
# the pantry item's emoji column - free text the user types - into raw() markup,
# so /pantry_items and /admin executed it. Found by planting payloads in a dev
# database and clicking, which is why this now runs on every commit.
class StoredXssTest < ActionDispatch::IntegrationTest
  PAYLOAD = %(<img src=x onerror="document.title='XSS-FIRED'">).freeze

  setup do
    @admin = family_members(:one)
    @household = households(:one)

    @household.pantry_items.create!(
      name: "Hostile #{PAYLOAD}", aisle_category: "Other", emoji: PAYLOAD, is_staple: true
    )

    @recipe = @household.recipes.create!(
      title: "Hostile #{PAYLOAD}",
      tags: "weeknight, #{PAYLOAD}",
      instructions: PAYLOAD,
      prep_time: 5, cook_time: 5, servings: 2
    )
    @recipe.recipe_ingredients.create!(
      name: "Hostile #{PAYLOAD}", unit: PAYLOAD, quantity: 1, aisle_category: "Other"
    )

    sign_in_as(@admin)
  end

  # Every page that renders household free text. A payload reaching any of these
  # unescaped is stored XSS against whoever opens the page next.
  def self.pages
    {
      "pantry" => -> { pantry_items_path },
      "admin dashboard" => -> { admin_root_path },
      "admin roster" => -> { admin_family_members_path },
      "recipes index" => -> { recipes_path },
      "recipe show" => -> { recipe_path(@recipe) },
      "recipe edit" => -> { edit_recipe_path(@recipe) },
      "meal plan" => -> { meal_plan_path(@household.current_meal_plan) },
      "grocery list" => -> { grocery_list_path },
      "family members" => -> { family_members_path },
      "preferences" => -> { edit_preferences_path }
    }
  end

  pages.each do |label, path|
    test "#{label} escapes stored markup" do
      get instance_exec(&path)
      assert_response :success

      assert_not_includes response.body, PAYLOAD,
        "#{label} rendered a stored payload as markup"
      assert_not_includes response.body, %(onerror="document.title),
        "#{label} emitted a live event handler from stored text"
    end
  end

  test "the escaped payload really is present, so the assertions above mean something" do
    get pantry_items_path

    assert_includes response.body, "&lt;img src=x onerror=",
      "the payload should still be on the page, escaped - otherwise these tests prove nothing"
  end
end
