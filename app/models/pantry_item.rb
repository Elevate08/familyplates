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
    { name: "Black Pepper", aisle_category: "Spices & Baking", emoji: "🌶️" },
    { name: "Olive Oil", aisle_category: "Pantry & Grains", emoji: "🫒" },
    { name: "Vegetable Oil", aisle_category: "Pantry & Grains", emoji: "🛢️" },
    { name: "Garlic Powder", aisle_category: "Spices & Baking", emoji: "🧄" },
    { name: "Onion Powder", aisle_category: "Spices & Baking", emoji: "🧅" },
    { name: "Italian Seasoning", aisle_category: "Spices & Baking", emoji: "🌿" },
    { name: "All-Purpose Flour", aisle_category: "Spices & Baking", emoji: "🌾" },
    { name: "Granulated Sugar", aisle_category: "Spices & Baking", emoji: "🍯" },
    { name: "Soy Sauce", aisle_category: "Pantry & Grains", emoji: "🥢" },
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

  def toggle_staple!
    update!(is_staple: !is_staple)
  end

  def display_emoji
    return emoji if emoji.present?

    self.class.emoji_for(name, aisle_category)
  end

  def self.emoji_for(name, category = nil)
    n = name.to_s.downcase
    case n
    when /olive oil/ then "🫒"
    when /vegetable oil|canola oil|sesame oil|oil/ then "🛢️"
    when /salt/ then "🧂"
    when /black pepper|pepper powder|peppercorn/ then "🌶️"
    when /garlic/ then "🧄"
    when /onion/ then "🧅"
    when /butter/ then "🧈"
    when /egg/ then "🥚"
    when /milk/ then "🥛"
    when /cream|sour cream/ then "🥛"
    when /cheese|cheddar|mozzarella|parmesan|feta/ then "🧀"
    when /flour/ then "🌾"
    when /sugar|honey|syrup/ then "🍯"
    when /soy sauce/ then "🥢"
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
