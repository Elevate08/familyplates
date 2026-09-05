class PantryItem < ApplicationRecord
  belongs_to :household

  CATEGORIES = [
    "Produce",
    "Meat & Seafood",
    "Dairy & Refrigerated",
    "Bakery",
    "Pantry & Grains",
    "Spices & Baking",
    "Frozen",
    "Other"
  ].freeze

  DEFAULT_STAPLES = [
    { name: "Salt", aisle_category: "Spices & Baking", emoji: "🧂" },
    { name: "Black Pepper", aisle_category: "Spices & Baking", emoji: "🫙" },
    { name: "Olive Oil", aisle_category: "Pantry & Grains", emoji: "🍾" },
    { name: "Vegetable Oil", aisle_category: "Pantry & Grains", emoji: "🌻" },
    { name: "Garlic Powder", aisle_category: "Spices & Baking", emoji: "🫙" },
    { name: "Onion Powder", aisle_category: "Spices & Baking", emoji: "🫙" },
    { name: "Italian Seasoning", aisle_category: "Spices & Baking", emoji: "🌿" },
    { name: "All-Purpose Flour", aisle_category: "Spices & Baking", emoji: "🌾" },
    { name: "Granulated Sugar", aisle_category: "Spices & Baking", emoji: "🥄" },
    { name: "Soy Sauce", aisle_category: "Pantry & Grains", emoji: "🍶" },
    { name: "Butter", aisle_category: "Dairy & Refrigerated", emoji: "🧈" },
    { name: "Eggs", aisle_category: "Dairy & Refrigerated", emoji: "🥚" },
    { name: "Garlic", aisle_category: "Produce", emoji: "🧄" },
    { name: "Onions", aisle_category: "Produce", emoji: "🧅" },
    { name: "Rice", aisle_category: "Pantry & Grains", emoji: "🍚" },
    { name: "Pasta", aisle_category: "Pantry & Grains", emoji: "🍝" }
  ].freeze

  validates :name, presence: true, uniqueness: { scope: :household_id, case_sensitive: false }
  validates :aisle_category, inclusion: { in: CATEGORIES }

  scope :staples, -> { where(is_staple: true) }
  scope :by_category, -> { order(:aisle_category, :name) }
  scope :low_stock, -> { where.not(low_stock_at: nil) }
  scope :stocked, -> { where(low_stock_at: nil) }

  # A staple that is running low is still a staple - it just stops shielding
  # itself from the grocery list until it has been bought again.
  scope :shielding, -> { staples.stocked }

  def toggle_staple!
    update!(is_staple: !is_staple)
  end

  def low_stock?
    low_stock_at.present?
  end

  # Both marks are idempotent, because the grocery list drives them from a
  # checkbox that can be toggled twice as easily as once, and from a device that
  # may retry.
  def mark_low!
    return self if low_stock?

    update!(low_stock_at: Time.current)
    self
  end

  def mark_restocked!
    return self unless low_stock?

    update!(low_stock_at: nil)
    self
  end

  def toggle_low!
    low_stock? ? mark_restocked! : mark_low!
  end

  # Whether this item is currently keeping itself off the grocery list.
  def shielding?
    is_staple? && !low_stock?
  end

  # The pantry item an ingredient line refers to, or nil.
  #
  # Matching is exact on a normalized name and deliberately does no substring
  # comparison - the same rule IngredientAggregator settled on after "Peanut
  # butter" matched the "Butter" staple and quietly vanished from the list.
  def self.matching(household, ingredient_name)
    return nil if household.nil? || ingredient_name.blank?

    target = normalize_for_match(ingredient_name)
    return nil if target.blank?

    household.pantry_items.find { |item| normalize_for_match(item.name) == target }
  end

  def self.normalize_for_match(value)
    value.to_s.downcase.strip.squeeze(" ").singularize
  end

  def display_emoji
    return emoji if emoji.present?

    self.class.emoji_for(name, aisle_category)
  end

  def self.emoji_for(name, category = nil)
    n = name.to_s.downcase
    case n
    when /olive oil/ then "🍾"
    when /vegetable oil|canola oil|sunflower oil|corn oil/ then "🌻"
    when /sesame oil|cooking oil|oil/ then "🍾"
    when /salt/ then "🧂"
    when /black pepper|pepper powder|peppercorn/ then "🫙"
    when /garlic powder|garlic salt/ then "🫙"
    when /onion powder|onion flakes/ then "🫙"
    when /garlic/ then "🧄"
    when /onion/ then "🧅"
    when /butter/ then "🧈"
    when /egg/ then "🥚"
    when /milk/ then "🥛"
    when /cream|sour cream/ then "🥛"
    when /cheese|cheddar|mozzarella|parmesan|feta/ then "🧀"
    when /flour/ then "🌾"
    when /sugar/ then "🥄"
    when /honey|syrup|maple/ then "🍯"
    when /soy sauce/ then "🍶"
    when /rice/ then "🍚"
    when /pasta|spaghetti|noodle/ then "🍝"
    when /bread|sourdough|bagel|bun/ then "🍞"
    when /tortilla|taco/ then "🌮"
    when /tomato/ then "🍅"
    when /chicken/ then "🍗"
    when /beef|steak|ground beef/ then "🥩"
    when /pork|bacon|sausage/ then "🥓"
    when /salmon|fish|tuna|shrimp/ then "🐟"
    when /lemon|lime/ then "🍋"
    when /potato/ then "🥔"
    when /corn/ then "🌽"
    when /broccoli/ then "🥦"
    when /avocado/ then "🥑"
    when /chili|spice|cumin|paprika|oregano|seasoning/ then "🌿"
    when /bean/ then "🫘"
    else
      case category
      when "Produce" then "🥬"
      when "Meat & Seafood" then "🥩"
      when "Dairy & Refrigerated" then "🧀"
      when "Bakery" then "🍞"
      when "Pantry & Grains" then "🌾"
      when "Spices & Baking" then "🧂"
      when "Frozen" then "🧊"
      else "📦"
      end
    end
  end
end
