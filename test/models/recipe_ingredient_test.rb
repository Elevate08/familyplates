require "test_helper"

class RecipeIngredientTest < ActiveSupport::TestCase
  setup do
    @recipe = recipes(:one)
  end

  test "automatically resolves aisle category from mapping if blank" do
    ingredient = @recipe.recipe_ingredients.build(name: "Fresh Garlic", raw_text: "2 cloves fresh garlic", quantity: 2, unit: "cloves")
    ingredient.valid?
    assert_equal "Produce", ingredient.aisle_category
  end

  test "records usage in IngredientAisleMapping on save" do
    assert_difference -> { IngredientAisleMapping.count }, 1 do
      @recipe.recipe_ingredients.create!(name: "Dragon Fruit", quantity: 1, unit: "piece", aisle_category: "Produce")
    end

    mapping = IngredientAisleMapping.find_by(name: "dragon fruit", household: @recipe.household)
    assert_not_nil mapping
    assert_equal "Produce", mapping.aisle_category
  end

  test "formats display quantity without trailing zeros" do
    i1 = RecipeIngredient.new(quantity: 2.0)
    assert_equal "2", i1.display_quantity

    i2 = RecipeIngredient.new(quantity: 1.5)
    assert_equal "1.5", i2.display_quantity
  end

  # --- Aisle classification ----------------------------------------------------
  #
  # "Other" is a real option in the form's select. Treating it as a synonym for
  # "unset" meant a deliberate choice was overwritten on every save. The column
  # defaulted to "Other", which is why the two could not be told apart.

  test "an explicitly chosen Other survives a save" do
    ingredient = @recipe.recipe_ingredients.create!(name: "Truffle Oil", aisle_category: "Other")

    assert_equal "Other", ingredient.reload.aisle_category

    ingredient.update!(quantity: 2)
    assert_equal "Other", ingredient.reload.aisle_category, "and survives later saves too"
  end

  test "an unset aisle is still classified" do
    ingredient = @recipe.recipe_ingredients.create!(name: "Chicken Breast")

    assert_equal "Meat & Seafood", ingredient.reload.aisle_category
  end

  test "an unset aisle the classifier cannot place falls back to Other" do
    ingredient = @recipe.recipe_ingredients.create!(name: "Zorblatt Powder")

    assert_equal "Other", ingredient.reload.aisle_category
  end

  test "the column no longer defaults, so absent means absent" do
    assert_nil RecipeIngredient.column_defaults["aisle_category"],
      "a default makes every new record claim an aisle it was never given"
  end

  # --- Query cost --------------------------------------------------------------
  #
  # Saving one fifteen-ingredient recipe used to issue 211 queries: the aisle
  # lookup ran three per ingredient, and re-deriving the mappings did a find_by
  # plus a save or destroy for each of the eight aisle categories.

  test "saving a fifteen-ingredient recipe stays well under the old query cost" do
    names = %w[Chicken Rice Onions Garlic Carrots Celery Butter Flour Milk
               Cheese Paprika Thyme Parsley Lemon Salt]

    queries = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      queries += 1 unless args.last[:name].to_s =~ /SCHEMA|TRANSACTION/
    end
    names.each { |name| @recipe.recipe_ingredients.create!(name: name) }
    ActiveSupport::Notifications.unsubscribe(sub)

    assert_equal names.length, @recipe.recipe_ingredients.where(name: names).count,
      "precondition: every ingredient saved, or the budget below means nothing"
    assert_operator queries, :<, 120,
      "#{queries} queries for 15 ingredients - was 211 before batching"
  end

  test "batching did not change the aisles it works out" do
    expected = {
      "Chicken" => "Meat & Seafood", "Rice" => "Pantry & Grains", "Onions" => "Produce",
      "Butter" => "Dairy & Refrigerated", "Flour" => "Spices & Baking", "Thyme" => "Other"
    }

    expected.each do |name, aisle|
      ingredient = @recipe.recipe_ingredients.create!(name: name)
      assert_equal aisle, ingredient.reload.aisle_category, "#{name} changed aisle"
    end
  end
end
