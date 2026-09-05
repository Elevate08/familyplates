require "test_helper"

class RecipeScraperTest < ActiveSupport::TestCase
  test "parses schema.org/Recipe JSON-LD correctly" do
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Delicious Chicken Parm</title>
          <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@type": "Recipe",
            "name": "Crispy Chicken Parmesan",
            "description": "Golden breaded chicken baked with marinara and melted mozzarella.",
            "prepTime": "PT15M",
            "cookTime": "PT25M",
            "recipeYield": "4 servings",
            "recipeIngredient": [
              "2 large chicken breasts, halved horizontally",
              "1 cup marinara sauce",
              "1.5 cups shredded mozzarella cheese",
              "1/2 cup grated parmesan cheese",
              "2 tbsp olive oil"
            ],
            "recipeInstructions": [
              { "@type": "HowToStep", "text": "Bread the chicken and sear in olive oil." },
              { "@type": "HowToStep", "text": "Top with marinara and mozzarella." },
              { "@type": "HowToStep", "text": "Bake at 400F for 15 minutes." }
            ]
          }
          </script>
        </head>
        <body></body>
      </html>
    HTML

    result = RecipeScraper.parse_html(html, "https://example.com/chicken-parm")

    assert_equal "Crispy Chicken Parmesan", result[:title]
    assert_equal 15, result[:prep_time]
    assert_equal 25, result[:cook_time]
    assert_equal 4, result[:servings]
    assert_equal 5, result[:ingredients].count
    assert_includes result[:instructions], "Bread the chicken"

    chicken_ing = result[:ingredients].find { |i| i[:name].downcase.include?("chicken") }
    assert_not_nil chicken_ing
    assert_equal "Meat & Seafood", chicken_ing[:aisle_category]
  end

  test "parses total_time, equipment dish sizes, and normalizes margarine to butter" do
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <script type="application/ld+json">
          {
            "@context": "https://schema.org",
            "@type": "Recipe",
            "name": "French Toast Casserole",
            "prepTime": "PT15M",
            "cookTime": "PT45M",
            "totalTime": "PT75M",
            "recipeYield": ["6", "1 (8x8-inch) casserole"],
            "recipeIngredient": [
              "1 tablespoon margarine, softened"
            ],
            "recipeInstructions": [
              { "@type": "HowToStep", "text": "Grease an 8x8-inch baking pan." },
              { "@type": "HowToStep", "text": "Dot with butter and bake." }
            ]
          }
          </script>
        </head>
        <body></body>
      </html>
    HTML

    result = RecipeScraper.parse_html(html, "https://example.com/casserole")
    assert_equal 15, result[:prep_time]
    assert_equal 45, result[:cook_time]
    assert_equal 75, result[:total_time]
    assert_includes result[:equipment], "8x8-inch"

    butter_ing = result[:ingredients].first
    assert_equal "Butter, softened", butter_ing[:name]
    assert_equal "Dairy & Refrigerated", butter_ing[:aisle_category]
  end

  test "parses OpenGraph fallback when no JSON-LD is present" do
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head>
          <title>Grandma's Secret Pie</title>
          <meta property="og:title" content="Grandma's Apple Pie" />
          <meta property="og:description" content="The best homemade apple pie recipe." />
        </head>
        <body></body>
      </html>
    HTML

    result = RecipeScraper.parse_html(html, "https://example.com/pie")
    assert_equal "Grandma's Apple Pie", result[:title]
    assert_equal "The best homemade apple pie recipe.", result[:description]
  end

  test "refuses to fetch a target the egress policy blocks, without attempting a connection" do
    logged = +""
    original = Rails.logger
    Rails.logger = Logger.new(StringIO.new(logged))

    begin
      %w[
        file:///etc/passwd
        ftp://example.com/secrets
        http://169.254.169.254/latest/meta-data/
        http://127.0.0.1:3000/admin
        http://10.0.0.1/
        http://localhost/
      ].each do |url|
        assert_nil RecipeScraper.call(url), "#{url} must not produce a recipe"
      end
    ensure
      Rails.logger = original
    end

    # The refusal is logged distinctly from "the site was down", so an operator
    # can tell an SSRF attempt from a broken link.
    assert_equal 6, logged.scan(/\[egress\] RecipeScraper refused/).length, logged
  end

  # --- @graph trees -------------------------------------------------------

  test "finds the recipe inside a WordPress @graph beside WebSite, breadcrumb and author nodes" do
    result = scrape_fixture("wordpress_graph.html", "https://hungryhomestead.test/dinner/weeknight-chicken-enchiladas/")

    assert_equal "Weeknight Chicken Enchiladas", result[:title]
    assert_equal "Rolled tortillas baked in red sauce & plenty of cheese.", result[:description]
    assert_equal 20, result[:prep_time]
    assert_equal 30, result[:cook_time]
    assert_equal 50, result[:total_time]
    # "8 servings" wins over the pan sitting in the same recipeYield array.
    assert_equal 8, result[:servings]
    assert result[:yields_leftovers]
    assert_equal 5, result[:ingredients].count
    assert_includes result[:equipment], "9x13-inch"
  end

  test "prefers the recipe node carrying ingredients over a stub of the same name in @graph" do
    html = <<~HTML
      <html><head><script type="application/ld+json">
      {"@context":"https://schema.org","@graph":[
        {"@type":"Recipe","name":"Stub","url":"https://example.com/stub"},
        {"@type":"Recipe","name":"Real Pot Roast","recipeIngredient":["3 lbs chuck roast","2 cups beef broth"],
         "recipeInstructions":[{"@type":"HowToStep","text":"Sear and braise."}]}
      ]}
      </script></head><body></body></html>
    HTML

    result = RecipeScraper.parse_html(html, "https://example.com/pot-roast")

    assert_equal "Real Pot Roast", result[:title]
    assert_equal 2, result[:ingredients].count
  end

  test "reads JSON-LD wrapped in a commented CDATA block" do
    result = scrape_fixture("cdata_html_instructions.html", "https://publisher.test/recipes/skillet-cornbread")

    assert_equal "Skillet Cornbread", result[:title]
    assert_equal "Crisp-edged cornbread baked in a screaming hot pan.", result[:description]
  end

  test "salvages two JSON-LD objects emitted back to back in one script tag" do
    html = <<~HTML
      <html><head><script type="application/ld+json">
      {"@context":"https://schema.org","@type":"WebSite","name":"Blog"}
      {"@context":"https://schema.org","@type":"Recipe","name":"Sheet Pan Salmon",
       "recipeIngredient":["4 salmon fillets"],"recipeInstructions":["Roast at 425F."]}
      </script></head><body></body></html>
    HTML

    result = RecipeScraper.parse_html(html, "https://example.com/salmon")

    assert_equal "Sheet Pan Salmon", result[:title]
  end

  # --- Instruction formatting --------------------------------------------

  test "numbers HowToSteps continuously across HowToSection headings" do
    result = scrape_fixture("wordpress_graph.html", "https://hungryhomestead.test/dinner/weeknight-chicken-enchiladas/")

    assert_equal <<~STEPS.strip, result[:instructions]
      Make the filling

      1. Stir the chicken together with 1 cup of the enchilada sauce.

      2. Warm the tortillas until pliable.

      Assemble and bake

      3. Roll the filling into each tortilla and place seam-side down in a 9x13-inch baking dish.

      4. Pour over the remaining sauce, top with cheese, and bake at 375F for 25 minutes.
    STEPS
  end

  test "splits an instruction blob delivered as one HTML list" do
    result = scrape_fixture("cdata_html_instructions.html", "https://publisher.test/recipes/skillet-cornbread")

    assert_match(/\A1\. Preheat the oven to 425F/, result[:instructions])
    assert_includes result[:instructions], "3. Pour the batter into the hot skillet"
    assert_not_includes result[:instructions], "<li>"
  end

  test "prefers HowToStep text over its abbreviated name and strips inline markup" do
    html = <<~HTML
      <html><head><script type="application/ld+json">
      {"@context":"https://schema.org","@type":"Recipe","name":"Braised Greens",
       "recipeIngredient":["1 bunch collard greens"],
       "recipeInstructions":[
         {"@type":"HowToStep","name":"Wash","text":"Wash the greens in <strong>cold</strong> water &amp; drain."},
         {"@type":"HowToStep","name":"Braise the greens for 45 minutes"}
       ]}
      </script></head><body></body></html>
    HTML

    result = RecipeScraper.parse_html(html, "https://example.com/greens")

    assert_equal "1. Wash the greens in cold water & drain.\n\n2. Braise the greens for 45 minutes",
                 result[:instructions]
  end

  # --- Microdata fallback -------------------------------------------------

  test "falls back to schema.org microdata when a legacy blog ships no JSON-LD" do
    result = scrape_fixture("microdata_blog.html", "https://prairiekitchen.test/recipes/icebox-rolls")

    assert_equal "Grandma Ruth's Icebox Rolls", result[:title]
    assert_equal "Soft dinner rolls that rise overnight in the refrigerator.", result[:description]
    assert_equal 25, result[:prep_time]
    assert_equal 18, result[:cook_time]
    # No totalTime in the markup, so it is the sum rather than the old 15-minute default.
    assert_equal 43, result[:total_time]
    assert_equal 24, result[:servings]
    assert_equal 4, result[:ingredients].count
    assert_includes result[:instructions], "1. Dissolve the yeast"
    assert_includes result[:instructions], "3. Chill overnight"

    margarine = result[:ingredients].third
    assert_equal "Butter, melted", margarine[:name]
    assert_equal "cup", margarine[:unit]
  end

  test "ignores microdata that carries only a name, leaving OpenGraph to answer" do
    html = <<~HTML
      <html><head>
        <meta property="og:title" content="Weeknight Ramen" />
        <meta property="og:description" content="A fast bowl of noodles." />
      </head>
      <body><div itemscope itemtype="https://schema.org/Recipe"><h1 itemprop="name">Site Header</h1></div></body></html>
    HTML

    result = RecipeScraper.parse_html(html, "https://example.com/ramen")

    assert_equal "Weeknight Ramen", result[:title]
  end

  # --- Images -------------------------------------------------------------

  test "resolves a relative ImageObject URL from a JSON-LD image array" do
    result = scrape_fixture("wordpress_graph.html", "https://hungryhomestead.test/dinner/weeknight-chicken-enchiladas/")

    assert_equal "https://hungryhomestead.test/wp-content/uploads/enchiladas-1200.jpg", result[:image_url]
  end

  test "reads contentUrl from a single ImageObject" do
    result = scrape_fixture("cdata_html_instructions.html", "https://publisher.test/recipes/skillet-cornbread")

    assert_equal "https://images.publisher.test/cornbread.jpg", result[:image_url]
  end

  test "falls back through og:image and twitter:image when the recipe carries no image" do
    result = scrape_fixture("microdata_blog.html", "https://prairiekitchen.test/recipes/icebox-rolls")
    assert_equal "https://prairiekitchen.test/images/rolls-full.jpg", result[:image_url]

    html = <<~HTML
      <html><head>
        <meta name="twitter:image" content="//cdn.example.com/pie.jpg" />
        <script type="application/ld+json">
        {"@context":"https://schema.org","@type":"Recipe","name":"Buttermilk Pie",
         "recipeIngredient":["1 cup buttermilk"],"recipeInstructions":["Bake."]}
        </script>
      </head><body></body></html>
    HTML

    twitter_only = RecipeScraper.parse_html(html, "https://example.com/pie")
    assert_equal "https://cdn.example.com/pie.jpg", twitter_only[:image_url]
  end

  # --- Resilience ---------------------------------------------------------

  test "reports a bot challenge page instead of importing it as a recipe" do
    result = RecipeScraper.parse_html_result(
      file_fixture("recipe_pages/anti_bot_challenge.html").read,
      "https://seriouseats.test/recipes/carbonara"
    )

    assert_not result.success?
    assert_equal :blocked_by_site, result.error
  end

  test "reports a page with no recipe markup at all as unparseable" do
    result = RecipeScraper.parse_html_result("%PDF-1.4 not html", "https://example.com/recipe.pdf")

    assert_not result.success?
    assert_equal :unparseable, result.error
  end

  test "distinguishes anti-bot, missing, failing, and timing-out sites" do
    assert_equal :blocked_by_site, fetch_error_for(status: 403)
    assert_equal :blocked_by_site, fetch_error_for(status: 429)
    assert_equal :not_found, fetch_error_for(status: 404)
    assert_equal :site_error, fetch_error_for(status: 503)
    assert_equal :timeout, fetch_error_for(raises: Net::ReadTimeout.new)
    assert_equal :unreachable, fetch_error_for(raises: SocketError.new("getaddrinfo failed"))
    assert_equal :blocked, fetch_error_for(raises: OutboundUrlPolicy::Rejected.new("private address"))
  end

  private

  def scrape_fixture(name, url)
    RecipeScraper.parse_html(file_fixture("recipe_pages/#{name}").read, url)
  end

  # Drives RecipeScraper through its real fetch path with the network seam
  # scripted, so the status-to-reason mapping is exercised rather than mocked.
  def fetch_error_for(status: nil, raises: nil)
    original = SafeHttpFetcher.method(:get_response)
    SafeHttpFetcher.define_singleton_method(:get_response) do |_url, headers: {}|
      raise raises if raises
      SafeHttpFetcher::Result.new(status: status, location: nil, body: "<html><body>nope</body></html>")
    end

    silence_scraper_logs { RecipeScraper.fetch("https://example.com/recipe").error }
  ensure
    SafeHttpFetcher.define_singleton_method(:get_response, original)
  end

  def silence_scraper_logs
    original = Rails.logger
    Rails.logger = Logger.new(File::NULL)
    yield
  ensure
    Rails.logger = original
  end
end
