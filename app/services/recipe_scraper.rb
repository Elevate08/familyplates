require "nokogiri"
require "open-uri"
require "json"

class RecipeScraper
  attr_reader :url, :html

  def self.call(url)
    new(url).scrape
  end

  def self.parse_html(html_content, url = nil)
    new(url, html_content: html_content).scrape
  end

  def initialize(url, html_content: nil)
    @url = url
    @html = html_content
  end

  def scrape
    @html ||= fetch_html
    doc = Nokogiri::HTML(@html)

    recipe_data = extract_json_ld_recipe(doc)

    if recipe_data
      build_recipe_from_json_ld(recipe_data, doc)
    else
      build_recipe_from_opengraph(doc)
    end
  end

  private

  def fetch_html
    URI.parse(url).open(
      "User-Agent" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 MealHub/1.0",
      read_timeout: 10
    ).read
  rescue StandardError => e
    Rails.logger.warn("RecipeScraper failed to fetch #{url}: #{e.message}")
    nil
  end

  def extract_json_ld_recipe(doc)
    doc.css('script[type="application/ld+json"]').each do |script|
      content = script.text.strip
      next if content.blank?

      begin
        data = JSON.parse(content)
        recipe = find_recipe_in_json(data)
        return recipe if recipe
      rescue JSON::ParserError
        next
      end
    end
    nil
  end

  def find_recipe_in_json(data)
    case data
    when Hash
      if data["@type"] == "Recipe" || Array(data["@type"]).include?("Recipe")
        return data
      elsif data["@graph"].is_a?(Array)
        return find_recipe_in_json(data["@graph"])
      end
    when Array
      data.each do |item|
        found = find_recipe_in_json(item)
        return found if found
      end
    end
    nil
  end

  def build_recipe_from_json_ld(data, doc)
    title = data["name"] || data["headline"] || doc.title
    description = data["description"]
    prep_time = parse_iso_duration(data["prepTime"])
    cook_time = parse_iso_duration(data["cookTime"])
    servings = parse_servings(data["recipeYield"])
    image_url = extract_image(data["image"]) || extract_og_image(doc)
    instructions = extract_instructions(data["recipeInstructions"])
    ingredients = extract_ingredients(data["recipeIngredient"])

    {
      title: title.to_s.strip,
      description: description.to_s.strip,
      prep_time: prep_time,
      cook_time: cook_time,
      servings: servings,
      source_url: url,
      image_url: image_url,
      instructions: instructions,
      ingredients: ingredients
    }
  end

  def build_recipe_from_opengraph(doc)
    title = doc.at('meta[property="og:title"]')&.[]("content") || doc.title || "Imported Recipe"
    description = doc.at('meta[property="og:description"]')&.[]("content")
    image_url = extract_og_image(doc)

    {
      title: title.to_s.strip,
      description: description.to_s.strip,
      prep_time: 15,
      cook_time: 20,
      servings: 4,
      source_url: url,
      image_url: image_url,
      instructions: "No structured instructions found. Please paste instructions here.",
      ingredients: []
    }
  end

  def parse_iso_duration(duration)
    return 15 if duration.blank?
    return duration.to_i if duration.is_a?(Numeric) || duration.to_s =~ /^\d+$/

    if duration =~ /PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/i
      hours = $1.to_i
      minutes = $2.to_i
      (hours * 60) + minutes
    else
      15
    end
  end

  def parse_servings(yield_val)
    return 4 if yield_val.blank?
    yield_str = yield_val.is_a?(Array) ? yield_val.first.to_s : yield_val.to_s
    yield_str[/(\d+)/, 1]&.to_i || 4
  end

  def extract_image(image_val)
    case image_val
    when String then image_val
    when Array then image_val.first.is_a?(Hash) ? image_val.first["url"] : image_val.first
    when Hash then image_val["url"]
    end
  end

  def extract_og_image(doc)
    doc.at('meta[property="og:image"]')&.[]("content")
  end

  def extract_instructions(instructions_data)
    case instructions_data
    when Array
      steps = instructions_data.map do |step|
        if step.is_a?(Hash)
          step["text"] || step["name"]
        else
          step.to_s
        end
      end.compact.reject(&:blank?)
      steps.each_with_index.map { |s, idx| "#{idx + 1}. #{s.strip}" }.join("\n\n")
    when String
      instructions_data.strip
    else
      "Follow recipe instructions."
    end
  end

  def extract_ingredients(ingredients_data)
    Array(ingredients_data).map do |raw_line|
      next if raw_line.blank?
      parsed = parse_ingredient_line(raw_line.to_s.strip)
      parsed
    end.compact
  end

  def parse_ingredient_line(raw)
    cleaned = raw.gsub(/\s+/, " ").strip

    # Extract quantity
    quantity = nil
    unit = nil
    name = cleaned

    if cleaned =~ /^([\d\/\.\s\u00BC-\u00BE\u2150-\u215E]+)\s*(cups?|c\.|tbsp|tbs|tablespoons?|tsp|teaspoons?|lbs?|pounds?|oz|ounces?|cloves?|cans?|bunches?|pinch|handful|slices?|stalks?|pkg|packages?)?\s+(?:of\s+)?(.+)$/i
      qty_str = $1.strip
      unit = $2&.downcase
      name = $3.strip

      quantity = parse_fraction(qty_str)
    end

    aisle = categorize_ingredient(name)

    {
      raw_text: cleaned,
      name: name.gsub(/^[\,\-\–]\s*/, "").strip.capitalize,
      quantity: quantity,
      unit: unit,
      aisle_category: aisle
    }
  end

  def parse_fraction(str)
    return 1.0 if str.blank?
    str = str.gsub("½", " 1/2").gsub("¼", " 1/4").gsub("¾", " 3/4").gsub("⅓", " 1/3").gsub("⅔", " 2/3")
    parts = str.split(/\s+/)
    total = 0.0
    parts.each do |part|
      if part.include?("/")
        num, denom = part.split("/").map(&:to_f)
        total += (denom.zero? ? 0 : num / denom)
      else
        total += part.to_f
      end
    end
    total.positive? ? total.round(2) : 1.0
  end

  def categorize_ingredient(name)
    n = name.downcase
    case n
    when /chicken|beef|pork|steak|turkey|salmon|fish|shrimp|bacon|sausage|kielbasa|tuna|lamb|prosciutto|meatball/
      "Meat & Seafood"
    when /milk|cream|cheese|cheddar|mozzarella|parmesan|butter|yogurt|sour cream|feta|ricotta|egg/
      "Dairy & Refrigerated"
    when /onion|garlic|tomato|potato|lettuce|bell pepper|pepper|spinach|carrot|broccoli|avocado|lime|lemon|cilantro|basil|parsley|cucumber|asparagus|zucchini|mushroom|ginger|celery/
      "Produce"
    when /bread|tortilla|bun|pita|bagel|crust|baguette|roll/
      "Bakery"
    when /flour|sugar|baking powder|baking soda|salt|black pepper|cumin|chili powder|oregano|paprika|cinnamon|vanilla|cinnamon|nutmeg|seasoning/
      "Spices & Baking"
    when /frozen|peas|corn|ice cream/
      "Frozen"
    when /rice|pasta|spaghetti|noodle|oil|olive oil|vinegar|soy sauce|broth|stock|tomato paste|crushed tomato|canned|bean|honey|sauce|salsa|sesame oil/
      "Pantry & Grains"
    else
      "Other"
    end
  end
end
