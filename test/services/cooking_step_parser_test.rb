require "test_helper"

class CookingStepParserTest < ActiveSupport::TestCase
  # --- Step splitting -----------------------------------------------------

  test "splits the numbered, section-headed shape the scraper writes" do
    steps = CookingStepParser.call(<<~TEXT)
      Make the filling

      1. Stir the chicken together with 1 cup of the sauce.

      2. Warm the tortillas until pliable.

      Assemble and bake

      3. Roll the filling into each tortilla.

      4. Bake until bubbling.
    TEXT

    assert_equal 4, steps.length
    assert_equal [ 1, 2, 3, 4 ], steps.map(&:number)
    assert_equal "Stir the chicken together with 1 cup of the sauce.", steps.first.text
    assert_equal [ "Make the filling", "Make the filling", "Assemble and bake", "Assemble and bake" ],
                 steps.map(&:section)
  end

  test "treats one line per step as one step per line when nothing is numbered" do
    steps = CookingStepParser.call("Boil the pasta.\nSimmer the sauce.\nServe.")

    assert_equal 3, steps.length
    assert_equal "Serve.", steps.last.text
    assert_nil steps.first.section
  end

  test "reads a colon-terminated line as a section heading" do
    steps = CookingStepParser.call("For the sauce:\nWhisk it together.\nFor the salad:\nToss and chill.")

    assert_equal 2, steps.length
    assert_equal "For the sauce", steps.first.section
    assert_equal "For the salad", steps.second.section
  end

  test "breaks a single run-on paragraph into sentences" do
    steps = CookingStepParser.call("Preheat the oven to 400 degrees. Toss the vegetables in oil. Roast until browned.")

    assert_equal 3, steps.length
    assert_equal "Toss the vegetables in oil.", steps.second.text
  end

  test "leaves a single-sentence instruction as one step" do
    steps = CookingStepParser.call("Cook meat, warm shells, assemble.")

    assert_equal 1, steps.length
    assert_equal "Cook meat, warm shells, assemble.", steps.first.text
  end

  test "keeps a trailing unnumbered line as a step rather than swallowing it as a heading" do
    steps = CookingStepParser.call("1. Preheat.\n2. Mix.\n3. Bake.\nEnjoy!")

    assert_equal 4, steps.length
    assert_equal "Enjoy!", steps.last.text
  end

  test "accepts Step-prefixed and parenthesised markers" do
    steps = CookingStepParser.call("Step 1: Chop the onion.\n2) Sweat it in butter.")

    assert_equal [ "Chop the onion.", "Sweat it in butter." ], steps.map(&:text)
  end

  test "returns nothing for blank instructions" do
    assert_empty CookingStepParser.call(nil)
    assert_empty CookingStepParser.call("   \n\n  ")
  end

  # --- Timer detection ----------------------------------------------------

  test "detects minutes, hours, and seconds" do
    steps = CookingStepParser.call(<<~TEXT)
      1. Simmer for 15 minutes.
      2. Bake for 1 hour.
      3. Blanch for 90 seconds.
    TEXT

    assert_equal [ 900, 3600, 90 ], steps.map { |step| step.timers.first.seconds }
  end

  test "counts a range from its low end so the cook looks early" do
    steps = CookingStepParser.call("Roast for 25 to 30 minutes, until browned.")

    timer = steps.first.timers.first
    assert_equal 1500, timer.seconds
    # The label still shows the range the recipe actually wrote.
    assert_equal "25 to 30 minutes", timer.label
  end

  test "reads mixed and unicode fractions" do
    steps = CookingStepParser.call("1. Rise for 1 1/2 hours.\n2. Rest ½ hour.")

    assert_equal 5400, steps.first.timers.first.seconds
    assert_equal 1800, steps.second.timers.first.seconds
  end

  test "finds several distinct timers in one step but not the same one twice" do
    steps = CookingStepParser.call("Sear for 3 minutes per side, then braise for 2 hours, turning after 2 hours.")

    assert_equal [ 180, 7200 ], steps.first.timers.map(&:seconds)
  end

  test "ignores numbers that are not durations" do
    steps = CookingStepParser.call("Heat the oven to 425 degrees F and grease a 9x13-inch pan for 4 servings.")

    assert_empty steps.first.timers
  end

  test "ignores durations too short to stand at the counter for or too long to wait out" do
    steps = CookingStepParser.call("1. Whisk for 5 seconds.\n2. Chill for 24 hours.")

    assert_empty steps.first.timers
    assert_empty steps.second.timers
  end

  test "formats a timer for both the chip and the countdown face" do
    steps = CookingStepParser.call("1. Bake 45 minutes.\n2. Braise 2 hours.\n3. Blanch 90 seconds.")

    assert_equal [ "45 min", "2 hr", "1 min 30 sec" ], steps.map { |step| step.timers.first.display }
    assert_equal [ "45:00", "2:00:00", "1:30" ], steps.map { |step| step.timers.first.clock }
  end

  test "a recipe exposes its own parsed steps" do
    recipe = households(:one).recipes.create!(title: "Parser Subject", instructions: "1. Sear.\n2. Simmer for 20 minutes.")

    assert_equal 2, recipe.cooking_steps.length
    assert_equal 1200, recipe.cooking_steps.second.timers.first.seconds
  end
end
