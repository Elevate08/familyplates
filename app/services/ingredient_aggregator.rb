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
    staples_map = load_staples_map
    raw_ingredients = collect_ingredients

    aggregated = {}

    raw_ingredients.each do |ing|
      norm_name = normalize_name(ing.name)
      key = "#{norm_name}_#{ing.unit.to_s.downcase}"

      if aggregated[key]
        aggregated[key][:quantity] += (ing.quantity || 1.0)
        aggregated[key][:sources] << ing.recipe.title unless aggregated[key][:sources].include?(ing.recipe.title)
      else
        is_staple = is_staple_item?(norm_name, staples_map)
        aisle = ing.aisle_category.presence || "Other"
        emoji = PantryItem.emoji_for(norm_name, aisle)

        aggregated[key] = {
          name: norm_name,
          quantity: ing.quantity || 1.0,
          unit: ing.unit,
          aisle_category: aisle,
          emoji: emoji,
          is_staple: is_staple,
          sources: [ ing.recipe.title ]
        }
      end
    end

    all_items = aggregated.values

    shopping_items = all_items.reject { |item| item[:is_staple] }
    pantry_items = all_items.select { |item| item[:is_staple] }

    grouped_all_by_aisle = AISLE_ORDER.each_with_object({}) do |aisle, hash|
      items_in_aisle = all_items.select { |i| i[:aisle_category] == aisle }
      # Sort so items to buy come first, then in-pantry items
      hash[aisle] = items_in_aisle.sort_by { |i| [ i[:is_staple] ? 1 : 0, i[:name] ] } if items_in_aisle.any?
    end

    {
      aisles: grouped_all_by_aisle,
      total_shopping_count: shopping_items.count,
      total_pantry_count: pantry_items.count
    }
  end

  private

  def collect_ingredients
    recipe_ids = meal_plan.meal_plan_slots.where.not(recipe_id: nil).where(is_leftover: false).pluck(:recipe_id)
    RecipeIngredient.where(recipe_id: recipe_ids).includes(:recipe)
  end

  def load_staples_map
    household.pantry_items.staples.pluck(:name).map { |name| normalize_for_match(name) }
  end

  # Exact match on a normalized name, with no substring comparison in either
  # direction. Substrings marked "Peanut butter", "Butternut squash",
  # "Rice vinegar" and "Pasta sauce" as already in the pantry against the stock
  # staple list, which silently dropped them from the shopping list. Word
  # boundaries fix only some of those, so the check does not guess at all.
  #
  # The two errors are not symmetric: a miss puts a spare line on the list, which
  # the shopper ignores. A false match means the ingredient is never bought and
  # that is discovered at dinner. So this deliberately prefers to under-match.
  def is_staple_item?(name, staples_list)
    staples_list.include?(normalize_for_match(name))
  end

  # Case, surrounding and repeated whitespace, and plurals are all noise here:
  # an ingredient "Egg" and a staple "Eggs" are the same thing. Anything beyond
  # that is a guess.
  def normalize_for_match(value)
    value.to_s.downcase.strip.squeeze(" ").singularize
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
