require "nokogiri"
require "json"

class RecipeScraper
  attr_reader :url, :html

  # What went wrong, when nothing came back. The controller turns these into
  # user-facing copy; keeping them symbols means the wording lives in one place
  # and the scraper stays free of view concerns.
  Result = Struct.new(:recipe, :error, keyword_init: true) do
    def success? = recipe.present?
  end

  def self.call(url)
    fetch(url).recipe
  end

  # Preferred entry point: same work as .call, but the caller learns *why* a
  # scrape produced nothing.
  def self.fetch(url)
    new(url).result
  end

  def self.parse_html(html_content, url = nil)
    new(url, html_content: html_content).scrape
  end

  def self.parse_html_result(html_content, url = nil)
    new(url, html_content: html_content).result
  end

  def initialize(url, html_content: nil)
    @url = url
    @html = html_content
  end

  def scrape
    result.recipe
  end

  def result
    @html ||= fetch_html
    # Without this, a refused or failed fetch fell through to Nokogiri::HTML(nil)
    # and produced a placeholder "Imported Recipe" carrying the rejected URL,
    # which made RecipeImportsController's "Could not fetch recipe" branch dead
    # code - nothing ever returned nil for it to catch.
    return failure(@error || :unreachable) if @html.blank?

    doc = parse_document(@html)
    return failure(:unparseable) if doc.nil?

    recipe_data = extract_json_ld_recipe(doc) || extract_microdata_recipe(doc)

    if recipe_data
      Result.new(recipe: build_recipe_from_json_ld(recipe_data, doc))
    elsif anti_bot_page?(doc)
      # A challenge page is a 200 carrying real HTML, so it can only be caught
      # here: no recipe markup, and a body that says "prove you are a browser".
      failure(:blocked_by_site)
    else
      og = build_recipe_from_opengraph(doc)
      og ? Result.new(recipe: og) : failure(:unparseable)
    end
  end

  private

  USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 FamilyPlates/1.0".freeze

  ANTI_BOT_MARKERS = [
    "just a moment",
    "enable javascript and cookies to continue",
    "checking your browser",
    "verify you are human",
    "cf-browser-verification",
    "access denied",
    "attention required!",
    "request unsuccessful. incapsula"
  ].freeze

  # Recursion guard for JSON-LD trees: publishers nest @graph inside @graph, and
  # a self-referential document must not take the request down with it.
  MAX_JSON_DEPTH = 12

  def failure(error)
    Result.new(recipe: nil, error: error)
  end

  def fetch_html
    response = SafeHttpFetcher.get_response(url, headers: { "User-Agent" => USER_AGENT })

    case response.status
    when 200..299
      response.body
    when 401, 403, 429
      Rails.logger.info("RecipeScraper turned away by #{url} (HTTP #{response.status})")
      @error = :blocked_by_site
      nil
    when 404, 410
      @error = :not_found
      nil
    else
      @error = :site_error
      nil
    end
  rescue OutboundUrlPolicy::Rejected => e
    # Distinct from a site simply being down: something asked this server to
    # fetch a target it is not allowed to reach.
    Rails.logger.warn("[egress] RecipeScraper refused #{url.inspect}: #{e.message}")
    @error = :blocked
    nil
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
    Rails.logger.warn("RecipeScraper timed out fetching #{url}: #{e.class}")
    @error = :timeout
    nil
  rescue StandardError => e
    Rails.logger.warn("RecipeScraper failed to fetch #{url}: #{e.class}: #{e.message}")
    @error = :unreachable
    nil
  end

  # Nokogiri is forgiving, but a response that is not HTML at all (a PDF, a JSON
  # API, a truncated body) still has to be turned away rather than parsed into an
  # empty document that yields a titleless "recipe".
  def parse_document(raw)
    doc = Nokogiri::HTML(raw)
    return nil if doc.nil? || doc.root.nil?
    doc
  rescue StandardError => e
    Rails.logger.warn("RecipeScraper could not parse HTML from #{url}: #{e.class}: #{e.message}")
    nil
  end

  def anti_bot_page?(doc)
    haystack = "#{doc.title} #{doc.at_css('body')&.text}".to_s.downcase
    return false if haystack.length > 4_000 # a real article, not a challenge stub

    ANTI_BOT_MARKERS.any? { |marker| haystack.include?(marker) }
  end

  def extract_json_ld_recipe(doc)
    candidates = []

    doc.css('script[type="application/ld+json"]').each do |script|
      parsed = parse_json_ld(script.text)
      next if parsed.nil?

      collect_recipes(parsed, candidates)
    end

    best_recipe(candidates)
  end

  # Publishers ship JSON-LD wrapped in CDATA, HTML comments or JS line comments,
  # and some emit two objects back to back in one tag. Each of those is a
  # JSON::ParserError to a plain parse, and each is worth one more attempt.
  # Trimming to the outermost brace or bracket covers every wrapper at once.
  def parse_json_ld(raw)
    content = raw.to_s.strip
    return nil if content.blank?

    # Drop the wrapper tokens first: their own brackets would otherwise become
    # the "outermost" ones and swallow the document.
    content = content.gsub(/<!\[CDATA\[|\]\]>|<!--|-->/, "")

    first = content.index(/[\[{]/)
    last = content.rindex(/[\]}]/)
    return nil if first.nil? || last.nil? || last < first

    content = content[first..last]

    JSON.parse(content)
  rescue JSON::ParserError
    # "}{"-joined objects: wrap them into an array and retry once.
    begin
      JSON.parse("[#{content.gsub(/\}\s*\{/, "},{")}]")
    rescue JSON::ParserError
      nil
    end
  end

  # Walks @graph trees (and mainEntity / itemListElement wrappers, which sites
  # use just as often) collecting every Recipe node rather than stopping at the
  # first, so a stub Recipe in a breadcrumb cannot beat the real one.
  def collect_recipes(data, found, depth = 0)
    return if depth > MAX_JSON_DEPTH

    case data
    when Array
      data.each { |item| collect_recipes(item, found, depth + 1) }
    when Hash
      found << data if recipe_node?(data)

      %w[@graph mainEntity mainEntityOfPage itemListElement hasPart].each do |key|
        nested = data[key]
        collect_recipes(nested, found, depth + 1) if nested.is_a?(Array) || nested.is_a?(Hash)
      end
    end
  end

  def recipe_node?(node)
    Array(node["@type"]).map { |t| t.to_s.downcase }.include?("recipe")
  end

  # More ingredients means more of an actual recipe; ties keep document order.
  def best_recipe(candidates)
    candidates.max_by { |c| [ Array(c["recipeIngredient"]).length, Array(c["recipeInstructions"]).length ] }
  end

  # Legacy food blogs (and anything still on a 2012 WordPress recipe plugin)
  # never emit JSON-LD, but do carry itemprop markup. Normalizing it into the
  # same shape as a JSON-LD node means one builder handles both.
  def extract_microdata_recipe(doc)
    scope = doc.xpath(
      '//*[@itemtype][contains(translate(@itemtype, "ABCDEFGHIJKLMNOPQRSTUVWXYZ", ' \
      '"abcdefghijklmnopqrstuvwxyz"), "schema.org/recipe")]'
    ).first
    return nil if scope.nil?

    props = Hash.new { |hash, key| hash[key] = [] }
    scope.xpath(".//*[@itemprop]").each do |node|
      name = node["itemprop"].to_s.strip
      next if name.blank?

      value = microdata_value(node, name)
      props[name] << value if value.present?
    end

    ingredients = props["recipeIngredient"].presence || props["ingredients"]
    instructions = props["recipeInstructions"].presence || props["instructions"]
    # itemprop="name" alone is every author bio and site header on the page. Only
    # markup that actually carries a recipe body is worth preferring over og.
    return nil if ingredients.empty? && instructions.empty?

    {
      "name" => props["name"].first || doc.title,
      "description" => props["description"].first,
      "prepTime" => props["prepTime"].first,
      "cookTime" => props["cookTime"].first,
      "totalTime" => props["totalTime"].first,
      "recipeYield" => (props["recipeYield"].presence || props["yield"]),
      "image" => props["image"].first,
      "tool" => props["tool"],
      "recipeIngredient" => ingredients,
      "recipeInstructions" => instructions
    }
  end

  URL_PROPS = %w[image url contentUrl thumbnailUrl].freeze

  def microdata_value(node, prop)
    value =
      case node.name
      when "meta" then node["content"]
      when "time" then node["datetime"].presence || node["content"].presence || node.text
      when "img" then node["src"].presence || node["content"]
      when "a", "link" then URL_PROPS.include?(prop) ? node["href"] : node.text
      else node["content"].presence || node.text
      end

    value = value.to_s.gsub(/\s+/, " ").strip
    URL_PROPS.include?(prop) ? absolutize(value) : value
  end

  def build_recipe_from_json_ld(data, doc)
    title = data["name"] || data["headline"] || doc.title
    description = clean_text(data["description"])
    prep_time = parse_iso_duration(data["prepTime"])
    cook_time = parse_iso_duration(data["cookTime"])
    # A missing totalTime must stay missing: defaulting it to 15 made every
    # recipe without one claim a total shorter than its own cook time.
    total_time = parse_iso_duration(data["totalTime"], default: nil)
    servings = parse_servings(data["recipeYield"])
    image_url = extract_image(data["image"]) || extract_og_image(doc)
    instructions = extract_instructions(data["recipeInstructions"])
    ingredients = extract_ingredients(data["recipeIngredient"])
    equipment = extract_equipment(data, instructions, description, doc)
    yields_leftovers = servings.to_i >= 6 || title.to_s =~ /casserole|lasagna|stew|chili|roast|soup|bake|enchilada|pulled pork|batch|pot roast/i

    {
      title: clean_text(title),
      description: description.to_s.strip,
      prep_time: prep_time,
      cook_time: cook_time,
      total_time: (total_time.to_i > 0 ? total_time : ((prep_time || 0) + (cook_time || 0))),
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
    title = clean_text(doc.at('meta[property="og:title"]')&.[]("content") || doc.title)
    # No title at all means nothing recipe-shaped was here. Saying so beats
    # importing a card called "Imported Recipe" for the user to clean up.
    return nil if title.blank?

    description = doc.at('meta[property="og:description"]')&.[]("content")

    {
      title: title,
      description: clean_text(description),
      prep_time: 15,
      cook_time: 20,
      servings: 4,
      source_url: url,
      image_url: extract_og_image(doc),
      instructions: "No structured instructions found. Please paste instructions here.",
      ingredients: []
    }
  end

  def parse_iso_duration(duration, default: 15)
    duration = duration.first if duration.is_a?(Array)
    return default if duration.blank?
    return duration.to_i if duration.is_a?(Numeric) || duration.to_s =~ /\A\d+\z/

    text = duration.to_s
    if text =~ /P(?:(\d+)D)?T(?:(\d+)H)?(?:(\d+)M)?/i && "#{$1}#{$2}#{$3}".present?
      ($1.to_i * 24 * 60) + ($2.to_i * 60) + $3.to_i
    elsif text =~ /(\d+)\s*(?:hours?|hrs?|h)\b/i
      ($1.to_i * 60) + text[/(\d+)\s*(?:minutes?|mins?|m)\b/i, 1].to_i
    elsif (minutes = text[/(\d+)\s*(?:minutes?|mins?)\b/i, 1])
      minutes.to_i
    else
      default
    end
  end

  EQUIPMENT_YIELD_PATTERN = /(?:pan|casserole|dish|sheet|pot|skillet|tin|loaf)/i

  # Sites put the pan in recipeYield ("1 (9x13-inch) casserole") as often as the
  # serving count, so equipment-shaped entries are skipped rather than read as
  # "serves 1".
  def parse_servings(yield_val)
    return 4 if yield_val.blank?

    entries = Array(yield_val).map { |entry| entry.to_s.strip }.reject(&:blank?)
    return 4 if entries.empty?

    plain = entries.reject { |entry| entry =~ EQUIPMENT_YIELD_PATTERN }
    (plain.presence || entries).each do |entry|
      number = entry[/(\d+)/, 1].to_i
      return number if number.positive?
    end

    4
  end

  def extract_image(image_val, depth = 0)
    return nil if depth > 4

    case image_val
    when String
      absolutize(image_val)
    when Array
      image_val.lazy.filter_map { |entry| extract_image(entry, depth + 1) }.first
    when Hash
      # ImageObject: url is canonical, contentUrl the common alternative, and
      # either may itself be an array or another nested ImageObject.
      candidate = image_val["url"] || image_val["contentUrl"] ||
                  image_val["thumbnailUrl"] || image_val["@id"]
      extract_image(candidate, depth + 1)
    end
  end

  OG_IMAGE_SELECTORS = [
    'meta[property="og:image"]',
    'meta[property="og:image:secure_url"]',
    'meta[name="og:image"]',
    'meta[name="twitter:image"]',
    'meta[property="twitter:image"]',
    'meta[name="twitter:image:src"]',
    'link[rel="image_src"]'
  ].freeze

  def extract_og_image(doc)
    OG_IMAGE_SELECTORS.each do |selector|
      node = doc.at(selector)
      next if node.nil?

      value = node["content"].presence || node["href"].presence
      return absolutize(value) if value.present?
    end
    nil
  end

  # Relative and protocol-relative image paths are common on self-hosted blogs
  # and are useless to store as-is.
  def absolutize(candidate)
    value = candidate.to_s.strip
    return nil if value.blank?
    return value if value.start_with?("http://", "https://", "data:")
    return nil if url.blank?

    URI.join(url, value).to_s
  rescue URI::Error, ArgumentError
    nil
  end

  # HowToStep, HowToSection, bare strings, nested lists, and text that is really
  # a blob of HTML all arrive through this one field, sometimes mixed together.
  def extract_instructions(instructions_data)
    lines = flatten_instructions(instructions_data)
    return "Follow recipe instructions." if lines.empty?

    step_number = 0
    lines.map do |line|
      next line[:text] if line[:heading]

      step_number += 1
      "#{step_number}. #{line[:text]}"
    end.join("\n\n")
  end

  def flatten_instructions(node, depth = 0, out = [])
    return out if depth > MAX_JSON_DEPTH

    case node
    when Array
      node.each { |item| flatten_instructions(item, depth + 1, out) }
    when Hash
      types = Array(node["@type"]).map { |type| type.to_s.downcase }
      children = node["itemListElement"] || node["steps"] || node["step"]

      if types.include?("howtosection") || (children.present? && !types.include?("howtostep"))
        heading = clean_text(node["name"])
        out << { text: heading, heading: true } if heading.present?
        flatten_instructions(children, depth + 1, out)
      else
        # HowToStep: text is authoritative. name is a short label that is often
        # only the first clause of it, so it is a fallback rather than a prefix.
        text = clean_text(node["text"]).presence || clean_text(node["name"]).presence ||
               clean_text(node["description"])
        out << { text: text, heading: false } if text.present?
      end
    when String
      split_instruction_text(node).each { |text| out << { text: text, heading: false } }
    end

    out
  end

  # A single string may be one step, an HTML <ol>, or paragraphs separated by
  # newlines. Splitting keeps the numbered output readable either way.
  def split_instruction_text(raw)
    text = raw.to_s
    return [] if text.blank?

    if text =~ /<\s*(?:li|p|br)\b/i
      fragment = Nokogiri::HTML.fragment(text)
      items = fragment.css("li").map { |li| clean_text(li.text) }
      items = fragment.css("p").map { |para| clean_text(para.text) } if items.empty?
      items = clean_text(fragment.text).split(/\n+/) if items.empty?
      return items.map(&:strip).reject(&:blank?)
    end

    cleaned = clean_text(text)
    return [] if cleaned.blank?

    parts = cleaned.split(/\n+/).map(&:strip).reject(&:blank?)
    parts.length > 1 ? parts : [ cleaned ]
  end

  # Descriptions and steps regularly arrive as HTML with entities and non-breaking
  # spaces in them; newlines survive so multi-step strings can still be split.
  def clean_text(value)
    text = value.to_s
    text = Nokogiri::HTML.fragment(text).text if text.include?("<") || text.include?("&")
    text.gsub(" ", " ").gsub(/[ \t]+/, " ").strip
  end

  def extract_ingredients(ingredients_data)
    Array(ingredients_data).flat_map do |raw_line|
      # Some sites group ingredients into sections the same way they group steps.
      case raw_line
      when Hash then Array(raw_line["itemListElement"] || raw_line["text"] || raw_line["name"])
      else [ raw_line ]
      end
    end.filter_map do |raw_line|
      line = clean_text(raw_line)
      next if line.blank?

      parse_ingredient_line(line)
    end
  end

  def extract_equipment(data, instructions, description, doc)
    raw_items = []

    # 1. From JSON-LD tool / equipment array
    tools = data["tool"] || data["equipment"]
    Array(tools).each do |tool|
      val = clean_text(tool.is_a?(Hash) ? tool["name"] : tool)
      raw_items << val if val.present?
    end

    # 2. From JSON-LD yield if it mentions pan/casserole/dish
    Array(data["recipeYield"]).each do |y|
      y_str = y.to_s.strip
      if y_str =~ EQUIPMENT_YIELD_PATTERN
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

  UNIT_PATTERN = /cups?|c\.|tbsp|tbs|tablespoons?|tsp|teaspoons?|lbs?|pounds?|oz|ounces?|cloves?|cans?|bunches?|pinch|handful|slices?|stalks?|pkg|packages?|quarts?|pints?|gallons?|sticks?|sprigs?|kilograms?|kg|grams?|g|milliliters?|ml|sheets?|jars?|bottles?|containers?|bags?|boxes?/i

  def parse_ingredient_line(raw)
    cleaned = raw.gsub(/\s+/, " ").strip

    # Extract quantity
    quantity = nil
    unit = nil
    name = cleaned

    if cleaned =~ /^([\d\/\.\s¼-¾⅐-⅞]+)\s*(#{UNIT_PATTERN})?\s+(?:of\s+)?(.+)$/
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
