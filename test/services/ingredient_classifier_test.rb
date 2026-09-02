require "test_helper"

# Characterization: this table was lifted verbatim out of RecipeScraper, where it
# was a private method reachable only via
# RecipeScraper.new("").send(:categorize_ingredient, name). Rule order is
# load-bearing and the extraction must not have disturbed it.
class IngredientClassifierTest < ActiveSupport::TestCase
  EXPECTED = {
    "Chicken" => "Meat & Seafood", "Salmon" => "Meat & Seafood", "Bacon" => "Meat & Seafood",
    "Milk" => "Dairy & Refrigerated", "Cheddar" => "Dairy & Refrigerated", "Eggs" => "Dairy & Refrigerated",
    "Onion" => "Produce", "Fresh Garlic" => "Produce", "Avocado" => "Produce",
    "Bread" => "Bakery", "Tortilla" => "Bakery",
    "Flour" => "Spices & Baking", "Paprika" => "Spices & Baking",
    "Frozen peas" => "Frozen",
    # "Ice cream" lands in Dairy, not Frozen: the Dairy rule matches "cream" and
    # is checked first. Recorded because it is what the code does, quirk and all
    # - a characterization test that "corrects" the behaviour it is meant to pin
    # proves nothing.
    "Ice cream" => "Dairy & Refrigerated",
    "Rice" => "Pantry & Grains", "Soy sauce" => "Pantry & Grains",
    "Zorblatt Powder" => "Other", "" => "Other"
  }.freeze

  test "classifies each ingredient exactly as the scraper's private method did" do
    EXPECTED.each do |name, aisle|
      assert_equal aisle, IngredientClassifier.call(name), "#{name.inspect} changed aisle"
    end
  end

  test "rule order is preserved where categories overlap" do
    # "butter" matches both Dairy and, via "butternut", nothing else - Dairy wins
    # because it is checked before Produce. "pepper" is in both Produce and
    # Spices; Produce is checked first.
    assert_equal "Dairy & Refrigerated", IngredientClassifier.call("Butter")
    assert_equal "Produce", IngredientClassifier.call("Bell pepper")
    assert_equal "Produce", IngredientClassifier.call("Black pepper")
  end

  test "unknown? distinguishes a guess of Other from a real answer" do
    assert IngredientClassifier.unknown?(nil)
    assert IngredientClassifier.unknown?("")
    assert IngredientClassifier.unknown?("Other")
    assert_not IngredientClassifier.unknown?("Produce")
  end

  test "nothing reaches the heuristic through send any more" do
    offenders = Dir.glob(Rails.root.join("app/**/*.rb")).select do |file|
      code = File.readlines(file).grep_v(/^\s*#/).join
      code.match?(/\.send\(:/)
    end

    assert_empty offenders, "private methods are being called through send"
  end
end
