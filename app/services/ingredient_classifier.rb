# Aisle from an ingredient name. A lookup table, shared by the scraper and aisle learning.
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

  # "Other" when nothing matches. Order matters: "butter" is Dairy before Produce, "pepper" is Produce before Spices.
  def self.call(name)
    n = name.to_s.downcase
    return UNKNOWN if n.blank?

    match = RULES.find { |pattern, _aisle| n.match?(pattern) }
    match ? match.last : UNKNOWN
  end

  # No opinion, so callers can tell a guess of Other from a user choosing Other.
  def self.unknown?(aisle)
    aisle.blank? || aisle == UNKNOWN
  end
end
