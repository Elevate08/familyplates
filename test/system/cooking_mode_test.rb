require "application_system_test_case"

# Cook Mode is almost entirely behaviour: which step is on screen, whether the
# drawer slid out, whether a countdown counts down. A request test renders the
# markup for all of it and proves none of it, so the interactive half is checked
# in a real browser - where `assert_no_browser_errors` also catches the wake lock
# throwing on a platform that has no such API.
#
# The small labels are uppercased in CSS, not in the DOM, so assertions against
# them are case-insensitive: Capybara reads the rendered text.
class CookingModeTest < ApplicationSystemTestCase
  setup do
    @household = households(:one)
    @recipe = @household.recipes.create!(
      title: "Browser Braise",
      instructions: "1. Brown the meat.\n2. Simmer for 20 minutes.\n3. Rest and serve."
    )
    @recipe.recipe_ingredients.create!(name: "Beef chuck", quantity: 2, unit: "lbs")
    @recipe.recipe_ingredients.create!(name: "Red wine", quantity: 1, unit: "cups")

    # Selenium keeps one window for the whole process and a sibling test resizes
    # it to a phone, so the width this file runs at is otherwise whatever ran
    # before it. Cook Mode's header collapses below the sm breakpoint, which
    # makes that difference visible - pin the window rather than inherit it.
    page.driver.browser.manage.window.resize_to(1400, 1000)

    sign_in_as(family_members(:one))
    visit cook_recipe_path(@recipe)
  end

  test "walks forward and back through the steps one at a time" do
    assert_text "Brown the meat"
    assert_no_text "Simmer for 20 minutes"
    assert_step 1

    click_on "Next Step"
    assert_text "Simmer for 20 minutes"
    assert_no_text "Brown the meat"
    assert_step 2

    click_on "Back"
    assert_text "Brown the meat"
    assert_step 1
  end

  test "the arrow keys move between steps" do
    find("body").send_keys(:arrow_right)
    assert_step 2

    find("body").send_keys(:arrow_left)
    assert_step 1
  end

  test "Back is unavailable on the first step and Next gives way to Finish on the last" do
    assert find("button", text: "Back").disabled?
    assert_no_link "Finish"

    click_on "Next Step"
    click_on "Next Step"

    assert_step 3
    assert_no_button "Next Step"
    click_on "Finish"

    assert_current_path recipe_path(@recipe)
  end

  test "the ingredient drawer opens, remembers its ticks, and closes on Escape" do
    assert_no_selector "[data-cook-mode-target='drawer']", visible: true

    click_on "Ingredients"
    assert_selector "[data-cook-mode-target='drawer']", visible: true
    assert_text "Beef chuck"

    check "cook_ingredient_#{@recipe.recipe_ingredients.first.id}"
    assert_selector "[data-cook-mode-target='remaining']", text: "1"

    find("body").send_keys(:escape)
    assert_no_selector "[data-cook-mode-target='drawer']", visible: true

    # The tick is per recipe and per device, so it survives a reload.
    visit cook_recipe_path(@recipe)
    click_on "Ingredients"
    assert_checked_field "cook_ingredient_#{@recipe.recipe_ingredients.first.id}"
    assert_selector "[data-cook-mode-target='remaining']", text: "1"
  end

  test "a detected duration becomes a countdown that starts on one tap" do
    click_on "Next Step"

    timer = find("[data-controller='step-timer']")
    assert timer.has_text?("20:00")
    assert timer.has_text?(/tap to start/i)

    timer.find("button", text: "20:00").click
    assert timer.has_text?(/tap to pause/i)
    # It is counting: the face has left its starting value within a second.
    assert timer.has_no_text?("20:00", wait: 3)

    timer.find("button", text: /reset/i).click
    assert timer.has_text?("20:00")
    assert timer.has_text?(/tap to start/i)
  end

  test "the wake lock says which state the screen is in rather than throwing" do
    # Which state depends on the platform - the API needs a secure context and is
    # missing entirely on some kitchen displays. Either answer is correct; a
    # controller that blew up on the way to one is not, and teardown's
    # assert_no_browser_errors is what catches that.
    #
    # visible: :all because the label collapses to the indicator dot below the
    # sm breakpoint, and the window this test inherits is whatever the test
    # before it left behind.
    assert_selector "[data-wake-lock-target='label']", text: /screen (stays on|may dim)/i, visible: :all
  end

  private

  def assert_step(number)
    assert_selector "[data-cook-mode-target='counter']", text: /step #{number} of 3/i
  end
end
