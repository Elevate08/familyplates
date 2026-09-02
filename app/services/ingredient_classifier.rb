# Guesses a supermarket aisle from an ingredient's name.
#
# This lived as a private method on RecipeScraper, which meant the only way to
# reach it was `RecipeScraper.new("").send(:categorize_ingredient, name)` -
# building a scraper with an empty URL purely to bypass Ruby's access control.
# It is not scraping logic; it is a lookup table, and both the scraper and the
# aisle-learning code need it.
class IngredientClassifier
  UNKNOWN = "Other".freeze

  RULES = [
    [ /chicken|beef|pork|steak|turkey|salmon|fish|shrimp|bacon|sausage|kielbasa|tuna|lamb|prosciutto|meatball/, "Meat & Seafood" ],
    [ /milk|cream|cheese|cheddar|mozzarella|parmesan|butter|margarine|yogurt|sour cream|feta|ricotta|egg/, "Dairy & Refrigerated" ],
    [ /onion|garlic|tomato|potato|lettuce|bell pepper|pepper|spinach|carrot|broccoli|avocado|lime|lemon|cilantro|basil|parsley|cucumber|asparagus|zucchini|mushroom|ginger|celery/, "Produce" ],
    [ /bread|tortilla|bun|pita|bagel|crust|baguette|roll/, "Bakery" ],
    [ /flour|sugar|baking powder|baking soda|salt|black pepper|cumin|chili powder|oregano|paprika|cinnamon|vanilla|cinnamon|nutmeg|seasoning/, "Spices & Baking" ],
    [ /frozen|peas|corn|ice cream/, "Frozen" ],
    [ /rice|pasta|spaghetti|noodle|oil|olive oil|vinegar|soy sauce|broth|stock|tomato paste|crushed tomato|canned|bean|honey|sauce|salsa|sesame oil/, "Pantry & Grains" ]
  ].freeze

  # Returns an aisle name, or "Other" when nothing matches. Rule order is
  # significant and preserved exactly as it was: "butter" reaches Dairy before
  # Produce can claim it, and "pepper" reaches Produce before Spices.
  def self.call(name)
    n = name.to_s.downcase
    return UNKNOWN if n.blank?

    match = RULES.find { |pattern, _aisle| n.match?(pattern) }
    match ? match.last : UNKNOWN
  end

  # True when the classifier had no opinion, so callers can tell "we guessed
  # Other" apart from "the user chose Other".
  def self.unknown?(aisle)
    aisle.blank? || aisle == UNKNOWN
  end
end
