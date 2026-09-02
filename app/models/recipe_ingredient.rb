class RecipeIngredient < ApplicationRecord
  belongs_to :recipe

  AISLE_CATEGORIES = [
    "Produce",
    "Meat & Seafood",
    "Dairy & Refrigerated",
    "Bakery",
    "Pantry & Grains",
    "Spices & Baking",
    "Frozen",
    "Other"
  ].freeze

  COMMON_UNITS = [
    "count",
    "cups",
    "cup",
    "tbsp",
    "tsp",
    "oz",
    "fl oz",
    "lbs",
    "lb",
    "g",
    "kg",
    "ml",
    "L",
    "cloves",
    "can",
    "cans",
    "slices",
    "fillets",
    "bunch",
    "heads",
    "pint",
    "quart",
    "pinch",
    "dash",
    "to taste",
    "pkg",
    "stalks",
    "jar",
    "bottle",
    "sprig"
  ].freeze

  def self.available_units(household = nil)
    db_units = if household
                 household.recipes.joins(:recipe_ingredients)
                          .where.not(recipe_ingredients: { unit: [ nil, "" ] })
                          .distinct.pluck(Arel.sql("recipe_ingredients.unit"))
    else
                 where.not(unit: [ nil, "" ]).distinct.pluck(Arel.sql("unit"))
    end
    (COMMON_UNITS + db_units).map(&:to_s).map(&:strip).reject(&:blank?).uniq.sort_by(&:downcase)
  end

  validates :name, presence: true
  validates :aisle_category, inclusion: { in: AISLE_CATEGORIES }

  before_validation :normalize_fields
  after_save :sync_aisle_mappings
  after_destroy :sync_aisle_mappings

  def display_quantity
    return nil if quantity.blank?
    if quantity == quantity.to_i
      quantity.to_i.to_s
    else
      quantity.to_s.sub(/\.0$/, "")
    end
  end

  private

  def normalize_fields
    if name.blank? && raw_text.present?
      self.name = raw_text.strip
    end

    # Only classify when no aisle was supplied. "Other" is a real option in the
    # form's select, so treating it as "unset" meant a deliberate choice was
    # overwritten on every save - file Truffle Oil under Other and it kept
    # jumping back to whatever the heuristic guessed.
    #
    # Callers that mean "I have no opinion" pass nil; the import paths used to
    # default to "Other", which is why this could not tell them apart.
    if aisle_category.blank? && name.present?
      suggested = IngredientAisleMapping.most_likely_aisle(name, recipe&.household)
      self.aisle_category = suggested if suggested.present?
    end

    self.aisle_category = IngredientClassifier::UNKNOWN if aisle_category.blank?
  end

  def sync_aisle_mappings
    return if name.blank?
    IngredientAisleMapping.sync_ingredient_usage!(name, recipe&.household)
  end
end
