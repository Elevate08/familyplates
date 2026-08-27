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
end
