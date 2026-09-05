class IngredientAggregator
  attr_reader :meal_plan, :household

  AISLE_ORDER = [
    "Produce",
    "Meat & Seafood",
    "Dairy & Refrigerated",
    "Bakery",
    "Pantry & Grains",
    "Spices & Baking",
    "Frozen",
    "Other"
  ].freeze

  def self.call(meal_plan)
    new(meal_plan).aggregate
  end

  def initialize(meal_plan)
    @meal_plan = meal_plan
    @household = meal_plan.household
  end

  def aggregate
    shielded = shielded_staple_names
    low_staples = low_staples_by_name
    raw_ingredients = collect_ingredients

    aggregated = {}

    raw_ingredients.each do |ing|
      norm_name = normalize_name(ing.name)
      key = "#{norm_name}_#{ing.unit.to_s.downcase}"

      if aggregated[key]
        aggregated[key][:quantity] += (ing.quantity || 1.0)
        aggregated[key][:sources] << ing.recipe.title unless aggregated[key][:sources].include?(ing.recipe.title)
      else
        match_key = normalize_for_match(norm_name)
        low_item = low_staples[match_key]
        aisle = ing.aisle_category.presence || "Other"
        emoji = PantryItem.emoji_for(norm_name, aisle)

        aggregated[key] = {
          name: norm_name,
          quantity: ing.quantity || 1.0,
          unit: ing.unit,
          aisle_category: aisle,
          emoji: emoji,
          # A staple only shields itself while it is stocked. Flagged low, it
          # stops reading as "already in the pantry" and joins the shopping list.
          is_staple: shielded.include?(match_key),
          restock: low_item.present?,
          pantry_item_id: low_item&.id,
          sources: [ ing.recipe.title ]
        }
      end
    end

    all_items = aggregated.values + orphan_restock_items(aggregated, low_staples)

    shopping_items = all_items.reject { |item| item[:is_staple] }
    pantry_items = all_items.select { |item| item[:is_staple] }
    restock_items = all_items.select { |item| item[:restock] }

    grouped_all_by_aisle = AISLE_ORDER.each_with_object({}) do |aisle, hash|
      items_in_aisle = all_items.select { |i| i[:aisle_category] == aisle }
      # Restock prompts first - somebody went out of their way to flag those -
      # then the rest of the shopping, then what is already on hand.
      hash[aisle] = items_in_aisle.sort_by { |i| [ sort_rank(i), i[:name] ] } if items_in_aisle.any?
    end

    {
      aisles: grouped_all_by_aisle,
      total_shopping_count: shopping_items.count,
      total_pantry_count: pantry_items.count,
      total_restock_count: restock_items.count
    }
  end

  private

  def collect_ingredients
    recipe_ids = meal_plan.meal_plan_slots.where.not(recipe_id: nil).where(is_leftover: false).pluck(:recipe_id)
    RecipeIngredient.where(recipe_id: recipe_ids).includes(:recipe)
  end

  def sort_rank(item)
    return 0 if item[:restock]

    item[:is_staple] ? 2 : 1
  end

  # Only a stocked staple shields itself. See PantryItem#shielding?.
  def shielded_staple_names
    household.pantry_items.shielding.pluck(:name).map { |name| normalize_for_match(name) }.to_set
  end

  def low_staples_by_name
    household.pantry_items.staples.low_stock.index_by { |item| normalize_for_match(item.name) }
  end

  # A staple that ran out is worth buying whether or not this week's recipes
  # happen to call for it. Running low on salt is exactly the case where nothing
  # on the meal plan would ever put it back on the list by itself.
  def orphan_restock_items(aggregated, low_staples)
    already_listed = aggregated.each_value.map { |item| normalize_for_match(item[:name]) }.to_set

    low_staples.filter_map do |match_key, item|
      next if already_listed.include?(match_key)

      {
        name: item.name,
        quantity: nil,
        unit: nil,
        aisle_category: item.aisle_category.presence || "Other",
        emoji: item.display_emoji,
        is_staple: false,
        restock: true,
        pantry_item_id: item.id,
        sources: []
      }
    end
  end

  # Matching is exact on a normalized name, with no substring comparison in
  # either direction. Substrings marked "Peanut butter", "Butternut squash",
  # "Rice vinegar" and "Pasta sauce" as already in the pantry against the stock
  # staple list, which silently dropped them from the shopping list. Word
  # boundaries fix only some of those, so the check does not guess at all.
  #
  # The two errors are not symmetric: a miss puts a spare line on the list, which
  # the shopper ignores. A false match means the ingredient is never bought and
  # that is discovered at dinner. So this deliberately prefers to under-match.
  #
  # Case, surrounding and repeated whitespace, and plurals are all noise here:
  # an ingredient "Egg" and a staple "Eggs" are the same thing. Anything beyond
  # that is a guess. PantryItem.normalize_for_match is the same rule, and the
  # two must stay in step - a name that matches here has to match there for the
  # grocery list's Restock checkbox to find its pantry row.
  def normalize_for_match(value)
    PantryItem.normalize_for_match(value)
  end

  def normalize_name(raw_name)
    raw_name.to_s
            .gsub(/^[\d\/\.\s]+/, "")
            .gsub(/\s*\([^)]*\)/, "")
            .gsub(/,.*$/, "")
            .strip
            .capitalize
  end
end
