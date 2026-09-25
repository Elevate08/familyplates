require "test_helper"

# Server-rendered counterpart to the DOM-sink work in A6.
#
# A6 swept app/javascript and stopped there, which missed app/helpers entirely:
# pantry_icon_tag interpolated the pantry item's emoji column - free text from
# the pantry form - into raw() markup, so /pantry_items executed it. Neither
# Brakeman nor any of the three reviews caught it; a payload planted in a dev
# database and one click did.
#
# So this does not sample. It plants a payload in *every* user-settable free-text
# column and requests *every* authenticated GET page in the app, because the
# lesson of that miss was that a hand-picked scope is the thing that fails.
class StoredXssTest < ActionDispatch::IntegrationTest
  # Text context: executes if it reaches the DOM as markup.
  TEXT_PAYLOAD = %(<img src=x onerror="document.title='XSS-FIRED'">).freeze

  # Attribute context: harmless as text, but escapes an unquoted or naively
  # quoted attribute - avatar_color lands in a style="" and image_url in a src="".
  ATTR_PAYLOAD = %(" onmouseover="document.title='XSS-FIRED).freeze

  setup do
    @household = households(:one)
    @admin = family_members(:one)

    @household.update!(
      name: "Hostile #{TEXT_PAYLOAD}"
    )

    @admin.update!(name: "Organizer #{TEXT_PAYLOAD}", avatar_color: ATTR_PAYLOAD, avatar_icon: TEXT_PAYLOAD)
    family_members(:two).update!(name: "Kid #{TEXT_PAYLOAD}", avatar_icon: TEXT_PAYLOAD)

    @household.pantry_items.create!(
      name: "Hostile #{TEXT_PAYLOAD}", aisle_category: "Other", emoji: TEXT_PAYLOAD, is_staple: true
    )

    @recipe = @household.recipes.create!(
      title: "Hostile #{TEXT_PAYLOAD}",
      description: TEXT_PAYLOAD,
      instructions: TEXT_PAYLOAD,
      equipment: TEXT_PAYLOAD,
      meal_types: TEXT_PAYLOAD,
      tags: "weeknight, #{TEXT_PAYLOAD}",
      image_url: ATTR_PAYLOAD,
      source_url: ATTR_PAYLOAD,
      prep_time: 5, cook_time: 5, servings: 2
    )
    @recipe.recipe_ingredients.create!(
      name: "Hostile #{TEXT_PAYLOAD}", raw_text: TEXT_PAYLOAD, unit: TEXT_PAYLOAD,
      quantity: 1, aisle_category: "Other"
    )

    @plan = @household.current_meal_plan
    @plan.update!(notes: TEXT_PAYLOAD)
    # The fixtures already occupy some slots, so take whichever days are free.
    @plan.meal_plan_slots.find_or_initialize_by(date: @plan.week_start_date + 4, meal_type: "dinner")
         .update!(custom_title: "Hostile #{TEXT_PAYLOAD}", notes: TEXT_PAYLOAD, family_member: @admin)
    @plan.meal_plan_slots.find_or_initialize_by(date: @plan.week_start_date + 5, meal_type: "dinner")
         .update!(recipe: @recipe, family_member: @admin)

    sign_in_as(@admin)
  end

  # Every authenticated GET route an admin can reach. Onboarding is excluded
  # because A1 closed it on a configured install; select_profile is covered
  # separately since it renders member names before anyone signs in.
  def authenticated_pages
    {
      "root" => root_path,
      "family members" => family_members_path,
      "preferences" => edit_preferences_path,
      "admin dashboard" => admin_root_path,
      "admin roster" => admin_family_members_path,
      "admin member edit" => edit_admin_family_member_path(@admin),
      "admin household" => edit_admin_household_path,
      "admin calendar" => edit_admin_calendar_path,
      "pantry" => pantry_items_path,
      "recipes index" => recipes_path,
      "recipe new" => new_recipe_path,
      "recipe show" => recipe_path(@recipe),
      "recipe edit" => edit_recipe_path(@recipe),
      "recipe import" => new_recipe_import_path,
      "meal plan" => meal_plan_path(@plan),
      "meal plan month" => meal_plan_path(@plan, view: "month"),
      # new_meal_plan / edit_meal_plan are routed by `resources :meal_plans` but
      # MealPlansController defines no such actions and there are no views, so
      # they 404. Dead routing surface, noted for Stream B, nothing to assert.
      "meal plan print" => print_meal_plan_path(@plan),
      "meal plan print month" => print_meal_plan_path(@plan, view: "month"),
      "grocery list" => grocery_list_path,
      "plan grocery list" => plan_grocery_list_path(@plan)
    }
  end

  def assert_no_live_markup(label)
    assert_not_includes response.body, TEXT_PAYLOAD,
      "#{label} rendered stored text as markup"
    assert_not_includes response.body, ATTR_PAYLOAD,
      "#{label} let stored text break out of an attribute"
    assert_no_match(/onerror="document\.title|onmouseover="document\.title/, response.body,
      "#{label} emitted a live event handler from stored text")
  end

  test "no authenticated page renders stored text as markup" do
    authenticated_pages.each do |label, path|
      get path
      # root and a few others redirect onward; follow until the page settles so
      # the assertion runs against what a browser actually displays.
      3.times { break unless response.redirect?; follow_redirect! }

      assert_response :success, "#{label} (#{path}) did not render"
      assert_no_live_markup(label)
    end
  end

  test "the profile picker escapes member names for anonymous visitors" do
    sign_out

    get select_profile_path

    assert_response :success
    assert_no_live_markup("select_profile")
  end

  test "the payloads really are on the pages, escaped" do
    get pantry_items_path
    assert_includes response.body, "&lt;img src=x onerror=",
      "the pantry payload should be present but escaped - otherwise these tests prove nothing"

    get recipe_path(@recipe)
    assert_includes response.body, "&lt;img src=x onerror=",
      "the recipe payload should be present but escaped"
  end
end
