class IngredientAisleMapping < ApplicationRecord
  belongs_to :household, optional: true

  validates :name, presence: true
  validates :aisle_category, inclusion: { in: RecipeIngredient::AISLE_CATEGORIES }
  validates :count, numericality: { greater_than_or_equal_to: 1 }

  before_validation :normalize_fields

  def self.sync_ingredient_usage!(raw_name, household = nil)
    clean_name = normalize_name(raw_name)
    return if clean_name.blank?

    h_id = extract_household_id(household)
    resolved_household = extract_household(household)
    return unless resolved_household

    # Query actual distinct recipe counts in this household for each aisle category
    counts_by_aisle = resolved_household.recipes.joins(:recipe_ingredients)
                                        .where("LOWER(recipe_ingredients.name) = ?", clean_name)
                                        .group("recipe_ingredients.aisle_category")
                                        .count

    # Update or prune mappings for each category
    RecipeIngredient::AISLE_CATEGORIES.each do |aisle|
      actual_count = counts_by_aisle[aisle] || 0
      mapping = find_by(household_id: h_id, name: clean_name, aisle_category: aisle)

      if actual_count > 0
        mapping ||= new(household_id: h_id, name: clean_name, aisle_category: aisle)
        mapping.count = actual_count
        mapping.save!
      elsif mapping
        mapping.destroy
      end
    end
  end

  def self.record_usage!(raw_name, aisle, household = nil)
    clean_name = normalize_name(raw_name)
    return if clean_name.blank? || aisle.blank?
    return unless RecipeIngredient::AISLE_CATEGORIES.include?(aisle)

    h_id = extract_household_id(household)
    if h_id.present?
      sync_ingredient_usage!(clean_name, household)
    else
      mapping = find_or_initialize_by(household_id: nil, name: clean_name, aisle_category: aisle)
      mapping.count = (mapping.new_record? ? 1 : (mapping.count || 0) + 1)
      mapping.save!
    end
  end

  def self.recalculate_all!(household = nil)
    resolved_household = extract_household(household)
    return unless resolved_household

    h_id = resolved_household.id
    where(household_id: h_id).destroy_all

    counts = resolved_household.recipes.joins(:recipe_ingredients)
                               .where.not(recipe_ingredients: { name: [ nil, "" ], aisle_category: [ nil, "" ] })
                               .group("LOWER(recipe_ingredients.name), recipe_ingredients.aisle_category")
                               .count

    counts.each do |(name, aisle), count|
      next unless RecipeIngredient::AISLE_CATEGORIES.include?(aisle)
      create!(household_id: h_id, name: name, aisle_category: aisle, count: count)
    end
  end

  def self.most_likely_aisle(raw_name, household = nil)
    clean_name = normalize_name(raw_name)
    return "Other" if clean_name.blank?

    h_id = extract_household_id(household)

    # 1. Household weighted mapping
    if h_id.present?
      household_mapping = where(household_id: h_id, name: clean_name).order(count: :desc).first
      return household_mapping.aisle_category if household_mapping
    end

    # 2. Global learned mapping
    global_mapping = where(household_id: nil, name: clean_name).order(count: :desc).first
    return global_mapping.aisle_category if global_mapping

    # 3. Check existing recipe ingredients in household
    resolved_household = extract_household(household)
    if resolved_household
      recipe_mapping = resolved_household.recipes.joins(:recipe_ingredients)
                                         .where("LOWER(recipe_ingredients.name) = ?", clean_name)
                                         .group("recipe_ingredients.aisle_category")
                                         .order(Arel.sql("COUNT(*) DESC"))
                                         .pluck(Arel.sql("recipe_ingredients.aisle_category"))
                                         .first
      return recipe_mapping if recipe_mapping.present?
    end

    # 4. Keyword heuristic categorization
    heuristic = RecipeScraper.new("").send(:categorize_ingredient, clean_name)
    return heuristic if heuristic.present? && heuristic != "Other"

    "Other"
  end

  def self.available_ingredients_with_aisles(household = nil)
    # Collect from IngredientAisleMapping, RecipeIngredient, and PantryItem defaults
    ingredients_map = {}

    # Seed with base defaults
    default_staples.each do |item|
      name = item[:name].strip
      key = name.downcase
      ingredients_map[key] = {
        name: name,
        aisle: item[:aisle],
        weight: item[:weight] || 1
      }
    end

    h_id = extract_household_id(household)

    # Overlay database mappings
    scope = where(household_id: [ nil, h_id ].compact)
    scope.find_each do |m|
      key = m.name.downcase
      display_name = m.name.titleize
      if ingredients_map[key].nil? || m.count > ingredients_map[key][:weight]
        ingredients_map[key] = {
          name: display_name,
          aisle: m.aisle_category,
          weight: m.count
        }
      end
    end

    # Overlay recipe ingredients from household
    resolved_household = extract_household(household)
    if resolved_household
      resolved_household.recipes.joins(:recipe_ingredients)
                        .group("recipe_ingredients.name, recipe_ingredients.aisle_category")
                        .order(Arel.sql("COUNT(*) DESC"))
                        .pluck(Arel.sql("recipe_ingredients.name, recipe_ingredients.aisle_category, COUNT(*)"))
                        .each do |name, aisle, count|
        next if name.blank?
        key = name.strip.downcase
        display_name = name.strip.titleize
        if ingredients_map[key].nil? || count > ingredients_map[key][:weight]
          ingredients_map[key] = {
            name: display_name,
            aisle: aisle,
            weight: count
          }
        end
      end
    end

    ingredients_map.values.sort_by { |i| [ -i[:weight], i[:name].downcase ] }
  end

  def self.extract_household_id(household)
    return nil if household.nil?
    if household.is_a?(Household)
      household.id
    elsif household.is_a?(Hash)
      household[:id] || household["id"]
    elsif household.is_a?(Integer) || household.is_a?(String)
      household.to_i
    elsif household.respond_to?(:id)
      household.id
    end
  end

  def self.extract_household(household)
    return nil if household.nil?
    return household if household.is_a?(Household)
    id = extract_household_id(household)
    id ? Household.find_by(id: id) : nil
  end

  def self.default_staples
    [
      { name: "Garlic", aisle: "Produce", weight: 10 },
      { name: "Onions", aisle: "Produce", weight: 10 },
      { name: "Yellow Onion", aisle: "Produce", weight: 10 },
      { name: "Red Onion", aisle: "Produce", weight: 10 },
      { name: "Tomatoes", aisle: "Produce", weight: 8 },
      { name: "Roma Tomatoes", aisle: "Produce", weight: 8 },
      { name: "Potatoes", aisle: "Produce", weight: 8 },
      { name: "Bell Pepper", aisle: "Produce", weight: 8 },
      { name: "Spinach", aisle: "Produce", weight: 8 },
      { name: "Carrots", aisle: "Produce", weight: 8 },
      { name: "Broccoli", aisle: "Produce", weight: 8 },
      { name: "Avocado", aisle: "Produce", weight: 8 },
      { name: "Lime", aisle: "Produce", weight: 8 },
      { name: "Lemon", aisle: "Produce", weight: 8 },
      { name: "Cilantro", aisle: "Produce", weight: 8 },
      { name: "Fresh Basil", aisle: "Produce", weight: 8 },
      { name: "Mushrooms", aisle: "Produce", weight: 8 },
      { name: "Celery", aisle: "Produce", weight: 8 },
      { name: "Asparagus", aisle: "Produce", weight: 8 },
      { name: "Zucchini", aisle: "Produce", weight: 8 },
      { name: "Chicken Breast", aisle: "Meat & Seafood", weight: 10 },
      { name: "Chicken Thighs", aisle: "Meat & Seafood", weight: 10 },
      { name: "Ground Beef", aisle: "Meat & Seafood", weight: 10 },
      { name: "Ground Turkey", aisle: "Meat & Seafood", weight: 10 },
      { name: "Bacon", aisle: "Meat & Seafood", weight: 8 },
      { name: "Pork Chops", aisle: "Meat & Seafood", weight: 8 },
      { name: "Salmon Fillets", aisle: "Meat & Seafood", weight: 8 },
      { name: "Shrimp", aisle: "Meat & Seafood", weight: 8 },
      { name: "Sausage", aisle: "Meat & Seafood", weight: 8 },
      { name: "Steak", aisle: "Meat & Seafood", weight: 8 },
      { name: "Butter", aisle: "Dairy & Refrigerated", weight: 10 },
      { name: "Eggs", aisle: "Dairy & Refrigerated", weight: 10 },
      { name: "Whole Milk", aisle: "Dairy & Refrigerated", weight: 8 },
      { name: "Heavy Cream", aisle: "Dairy & Refrigerated", weight: 8 },
      { name: "Cheddar Cheese", aisle: "Dairy & Refrigerated", weight: 8 },
      { name: "Mozzarella Cheese", aisle: "Dairy & Refrigerated", weight: 8 },
      { name: "Parmesan Cheese", aisle: "Dairy & Refrigerated", weight: 8 },
      { name: "Sour Cream", aisle: "Dairy & Refrigerated", weight: 8 },
      { name: "Greek Yogurt", aisle: "Dairy & Refrigerated", weight: 8 },
      { name: "Cream Cheese", aisle: "Dairy & Refrigerated", weight: 8 },
      { name: "Bread", aisle: "Bakery", weight: 8 },
      { name: "Tortillas", aisle: "Bakery", weight: 8 },
      { name: "Hamburger Buns", aisle: "Bakery", weight: 8 },
      { name: "Sourdough Bread", aisle: "Bakery", weight: 8 },
      { name: "Pita Bread", aisle: "Bakery", weight: 8 },
      { name: "Olive Oil", aisle: "Pantry & Grains", weight: 10 },
      { name: "Vegetable Oil", aisle: "Pantry & Grains", weight: 8 },
      { name: "White Rice", aisle: "Pantry & Grains", weight: 8 },
      { name: "Jasmine Rice", aisle: "Pantry & Grains", weight: 8 },
      { name: "Brown Rice", aisle: "Pantry & Grains", weight: 8 },
      { name: "Pasta", aisle: "Pantry & Grains", weight: 8 },
      { name: "Spaghetti", aisle: "Pantry & Grains", weight: 8 },
      { name: "Penne Pasta", aisle: "Pantry & Grains", weight: 8 },
      { name: "Chicken Broth", aisle: "Pantry & Grains", weight: 8 },
      { name: "Beef Broth", aisle: "Pantry & Grains", weight: 8 },
      { name: "Black Beans", aisle: "Pantry & Grains", weight: 8 },
      { name: "Diced Tomatoes", aisle: "Pantry & Grains", weight: 8 },
      { name: "Tomato Paste", aisle: "Pantry & Grains", weight: 8 },
      { name: "Soy Sauce", aisle: "Pantry & Grains", weight: 8 },
      { name: "Honey", aisle: "Pantry & Grains", weight: 8 },
      { name: "Salt", aisle: "Spices & Baking", weight: 10 },
      { name: "Black Pepper", aisle: "Spices & Baking", weight: 10 },
      { name: "Garlic Powder", aisle: "Spices & Baking", weight: 10 },
      { name: "Onion Powder", aisle: "Spices & Baking", weight: 10 },
      { name: "All-Purpose Flour", aisle: "Spices & Baking", weight: 10 },
      { name: "Granulated Sugar", aisle: "Spices & Baking", weight: 10 },
      { name: "Brown Sugar", aisle: "Spices & Baking", weight: 8 },
      { name: "Baking Powder", aisle: "Spices & Baking", weight: 8 },
      { name: "Baking Soda", aisle: "Spices & Baking", weight: 8 },
      { name: "Cumin", aisle: "Spices & Baking", weight: 8 },
      { name: "Chili Powder", aisle: "Spices & Baking", weight: 8 },
      { name: "Smoked Paprika", aisle: "Spices & Baking", weight: 8 },
      { name: "Oregano", aisle: "Spices & Baking", weight: 8 },
      { name: "Italian Seasoning", aisle: "Spices & Baking", weight: 8 },
      { name: "Frozen Peas", aisle: "Frozen", weight: 8 },
      { name: "Frozen Corn", aisle: "Frozen", weight: 8 }
    ]
  end

  def self.normalize_name(name)
    name.to_s.strip.downcase
  end

  private

  def normalize_fields
    self.name = self.class.normalize_name(name)
    self.count = 1 if count.blank? || count < 1
  end
end
