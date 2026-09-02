require "nokogiri"
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
    # Without this, a refused or failed fetch fell through to Nokogiri::HTML(nil)
    # and produced a placeholder "Imported Recipe" carrying the rejected URL,
    # which made RecipeImportsController's "Could not fetch recipe" branch dead
    # code - nothing ever returned nil for it to catch.
    return nil if @html.blank?

    doc = Nokogiri::HTML(@html)

    recipe_data = extract_json_ld_recipe(doc)

    if recipe_data
      build_recipe_from_json_ld(recipe_data, doc)
    else
      build_recipe_from_opengraph(doc)
    end
  end

  private

  USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 FamilyPlates/1.0".freeze

  def fetch_html
    SafeHttpFetcher.get(url, headers: { "User-Agent" => USER_AGENT })
  rescue OutboundUrlPolicy::Rejected => e
    # Distinct from a site simply being down: something asked this server to
    # fetch a target it is not allowed to reach.
    Rails.logger.warn("[egress] RecipeScraper refused #{url.inspect}: #{e.message}")
    nil
  rescue StandardError => e
    Rails.logger.warn("RecipeScraper failed to fetch #{url}: #{e.class}: #{e.message}")
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
    total_time = parse_iso_duration(data["totalTime"])
    servings = parse_servings(data["recipeYield"])
    image_url = extract_image(data["image"]) || extract_og_image(doc)
    instructions = extract_instructions(data["recipeInstructions"])
    ingredients = extract_ingredients(data["recipeIngredient"])
    equipment = extract_equipment(data, instructions, description, doc)
    yields_leftovers = servings.to_i >= 6 || title.to_s =~ /casserole|lasagna|stew|chili|roast|soup|bake|enchilada|pulled pork|batch|pot roast/i

    {
      title: title.to_s.strip,
      description: description.to_s.strip,
      prep_time: prep_time,
      cook_time: cook_time,
      total_time: (total_time > 0 ? total_time : ((prep_time || 0) + (cook_time || 0))),
      equipment: equipment,
      servings: servings,
      yields_leftovers: yields_leftovers,
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

  def extract_equipment(data, instructions, description, doc)
    raw_items = []

    # 1. From JSON-LD tool / equipment array
    tools = data["tool"] || data["equipment"]
    Array(tools).each do |t|
      val = (t.is_a?(Hash) ? t["name"] : t.to_s).strip
      raw_items << val if val.present?
    end

    # 2. From JSON-LD yield if it mentions pan/casserole/dish
    Array(data["recipeYield"]).each do |y|
      y_str = y.to_s.strip
      if y_str =~ /(?:pan|casserole|dish|sheet|pot|skillet|tin|loaf)/i
        cleaned = y_str.gsub(/^1\s*\((.*?)\)\s*/, '\1 ').strip
        raw_items << cleaned if cleaned.present?
      end
    end

    # 3. Scan instructions & description for dish/pan dimensions and equipment
    all_text = "#{instructions} #{description}"
    pattern = /(?:an?\s+)?(\d+(?:\.\d+)?(?:\s*(?:x|by|\*)\s*\d+(?:\.\d+)?)*(?:\s*-\s*inch|\s*inch|\s*\")?\s*(?:baking pan|baking dish|casserole dish|casserole|cake pan|pie plate|pie dish|pie pan|springform pan|loaf pan|sheet pan|roasting pan|baking sheet|muffin tin|muffin pan|cast[- ]iron skillet|skillet|frying pan|Dutch oven|saucepan|stockpot|slow cooker|instant pot|air fryer|bundt pan|ramekins?))/i

    all_text.scan(pattern).each do |match|
      found = match.first.strip
      raw_items << found if found.present?
    end

    # Dimension-aware deduplication (e.g. consolidate '8x8-inch casserole' and '8x8-inch baking pan')
    dimension_regex = /(\d+(?:\.\d+)?(?:\s*(?:x|by|\*)\s*\d+(?:\.\d+)?)*(?:\s*-\s*inch|\s*inch|\s*\")?)/i
    grouped_by_dim = {}
    unmatched = []

    raw_items.each do |item|
      cleaned = item.to_s.strip
      next if cleaned.blank? || cleaned =~ /^\d+$/ || cleaned.length < 3

      dim_match = cleaned.match(dimension_regex)
      dim_key = dim_match ? dim_match[1].gsub(/\s+/, "").downcase : nil

      if dim_key.present? && dim_key.length > 1
        grouped_by_dim[dim_key] ||= []
        grouped_by_dim[dim_key] << cleaned
      else
        unmatched << cleaned
      end
    end

    results = []
    grouped_by_dim.each do |_dim, group_items|
      preferred = group_items.find { |i| i =~ /baking pan|baking dish|casserole dish|sheet pan|skillet/i } || group_items.first
      results << preferred.capitalize
    end

    unmatched.each do |item|
      results << item.capitalize unless results.any? { |r| r.downcase.include?(item.downcase) }
    end

    results.uniq.join(", ").presence
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

    # Normalize margarine/oleo to Butter
    if name =~ /^margarine/i
      name = name.sub(/^margarine/i, "Butter")
      cleaned = cleaned.sub(/margarine/i, "butter")
    end

    aisle = IngredientAisleMapping.most_likely_aisle(name)

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
    IngredientClassifier.call(name)
  end
end
