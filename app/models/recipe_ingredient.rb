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

  # Bulk saves suspend per-row resync and do each distinct name once. Otherwise a 15-ingredient import recomputes the same counts 15 times.
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

    # Classify only when no aisle was supplied. "Other" is a real choice, not unset.
    # Callers with no opinion pass nil.
    if aisle_category.blank? && name.present?
      suggested = IngredientAisleMapping.most_likely_aisle(name, recipe&.household)
      self.aisle_category = suggested if suggested.present?
    end

    self.aisle_category = IngredientClassifier::UNKNOWN if aisle_category.blank?
  end

  def sync_aisle_mappings
    return if self.class.aisle_sync_suspended?

    # Resync the old name too. Leaving it kept the typo at the top of autocomplete, which sorts by weight.
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
