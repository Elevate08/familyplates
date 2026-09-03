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

  # Saving a recipe saves every ingredient, and each one used to re-derive the
  # aisle mappings for its own name - so importing a fifteen-ingredient recipe
  # did that fifteen times over, most of it recomputing counts that the next
  # ingredient would recompute again. Bulk callers suspend it and resync each
  # distinct name once when the whole recipe has landed.
  def self.without_aisle_sync
    previous = Thread.current[:familyplates_suspend_aisle_sync]
    Thread.current[:familyplates_suspend_aisle_sync] = true
    yield
  ensure
    Thread.current[:familyplates_suspend_aisle_sync] = previous
  end

  def self.aisle_sync_suspended?
    Thread.current[:familyplates_suspend_aisle_sync].present?
  end

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
    return if self.class.aisle_sync_suspended?

    # Both names, when one replaced the other. Re-syncing only the current name
    # left the old one's mapping behind at its full count forever - correcting
    # "chikcen breast" to "chicken breast" kept the typo in the autocomplete
    # list, and it sorts by weight so it stayed near the top.
    [ name, previous_name ].compact_blank.uniq.each do |ingredient_name|
      IngredientAisleMapping.sync_ingredient_usage!(ingredient_name, recipe&.household)
    end
  end

  # The name this record had before the save that is now committing. nil unless
  # the name actually changed.
  def previous_name
    saved_change_to_name? ? saved_changes["name"]&.first : nil
  end
end
