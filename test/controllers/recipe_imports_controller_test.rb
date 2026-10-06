require "test_helper"

class RecipeImportsControllerTest < ActionDispatch::IntegrationTest
  include SlowDripHelper

  setup do
    @admin = family_members(:one)
    sign_in_as(@admin)
  end

  test "should get new" do
    get new_recipe_import_url
    assert_response :success
  end

  test "should handle blank url" do
    post recipe_imports_url, params: { url: "" }
    assert_redirected_to new_recipe_import_url
  end

  test "should import recipe and redirect to recipe show page" do
    scraped_data = {
      title: "French Toast Casserole",
      description: "Delicious breakfast casserole",
      prep_time: 15,
      cook_time: 45,
      servings: 6,
      source_url: "https://www.allrecipes.com/recipe/22389/french-toast-casserole/",
      instructions: "1. Line pan with bread.\n2. Bake.",
      ingredients: [
        { raw_text: "5 cups bread cubes", name: "Bread cubes", quantity: 5.0, unit: "cups", aisle_category: "Bakery" }
      ]
    }

    original_fetch = RecipeScraper.method(:fetch)
    RecipeScraper.define_singleton_method(:fetch) { |_url| RecipeScraper::Result.new(recipe: scraped_data) }

    begin
      assert_difference("Recipe.count", 1) do
        post recipe_imports_url, params: { url: "https://www.allrecipes.com/recipe/22389/french-toast-casserole/" }
      end
      recipe = Recipe.last
      assert_redirected_to edit_recipe_url(recipe)
      assert_equal "French Toast Casserole", recipe.title
      assert_equal 1, recipe.recipe_ingredients.count
      assert_includes flash[:notice], "Imported"
    ensure
      RecipeScraper.define_singleton_method(:fetch, original_fetch)
    end
  end

  test "should redirect with alert if recipe URL already imported" do
    recipes(:one).update!(source_url: "https://example.com/existing-tacos")

    post recipe_imports_url, params: { url: "https://example.com/existing-tacos" }
    assert_redirected_to recipe_url(recipes(:one))
    assert_includes flash[:alert], "already saved as"
  end

  test "should redirect with alert if recipe title already exists" do
    scraped_data = {
      title: recipes(:one).title,
      description: "Another taco",
      prep_time: 15,
      cook_time: 20,
      servings: 4,
      source_url: "https://example.com/different-tacos",
      instructions: "Cook.",
      ingredients: []
    }

    original_fetch = RecipeScraper.method(:fetch)
    RecipeScraper.define_singleton_method(:fetch) { |_url| RecipeScraper::Result.new(recipe: scraped_data) }

    begin
      assert_no_difference("Recipe.count") do
        post recipe_imports_url, params: { url: "https://example.com/different-tacos" }
      end
      assert_redirected_to recipe_url(recipes(:one))
      assert_includes flash[:alert], "already in your recipe box"
    ensure
      RecipeScraper.define_singleton_method(:fetch, original_fetch)
    end
  end

  test "a blocked import URL is refused with the ordinary error and creates nothing" do
    assert_no_difference "Recipe.count" do
      post recipe_imports_url, params: { url: "http://169.254.169.254/latest/meta-data/" }
    end

    assert_redirected_to new_recipe_import_url
    assert_equal "Could not fetch recipe from that web address. Please check the link or add manually.", flash[:alert]
  end

  test "a site that trickles its response is cut off and the import says it timed out" do
    with_slow_drip_server do |url|
      with_fetch_timeout(2) do
        assert_no_difference "Recipe.count" do
          post recipe_imports_url, params: { url: url }
        end
      end
    end

    assert_redirected_to new_recipe_import_url
    assert_equal RecipeImportsController::IMPORT_FAILURE_MESSAGES[:timeout], flash[:alert]
  end

  test "a second import while one is fetching is refused at once, without fetching" do
    slot = RecipeImportsController::FETCH_SLOT
    held = Queue.new
    release = Queue.new
    fetching = Thread.new { slot.synchronize { held << true; release.pop } }
    held.pop

    log = StringIO.new
    original_logger = Rails.logger
    begin
      Rails.logger = Logger.new(log)
      original_fetch = RecipeScraper.method(:fetch)
      RecipeScraper.define_singleton_method(:fetch) { |_url| raise "must not fetch while another import runs" }

      assert_no_difference "Recipe.count" do
        post recipe_imports_url, params: { url: "https://example.com/recipes/busy" }
      end
    ensure
      Rails.logger = original_logger
      RecipeScraper.define_singleton_method(:fetch, original_fetch)
      release << true
      fetching.join
    end

    assert_redirected_to new_recipe_import_url
    assert_equal "Another recipe import is running. Please try again in a moment.", flash[:alert]
    assert_includes log.string, "[import] fetch_slot_busy household_id=#{@admin.household_id}"
    busy_line = log.string.lines.find { |line| line.include?("fetch_slot_busy") }
    assert_not_includes busy_line, "example.com", "the refusal must not log the URL"
  end

  test "the fetch slot is free again after a fetch times out or raises" do
    slot = RecipeImportsController::FETCH_SLOT

    with_scrape_failure(:timeout) do
      post recipe_imports_url, params: { url: "https://example.com/recipes/slow" }
    end
    assert_includes flash[:alert], "took too long"
    assert_not slot.locked?, "a failed fetch must release the slot"

    original_fetch = RecipeScraper.method(:fetch)
    RecipeScraper.define_singleton_method(:fetch) { |_url| raise "boom" }
    begin
      assert_raises(RuntimeError) { post recipe_imports_url, params: { url: "https://example.com/recipes/raises" } }
    ensure
      RecipeScraper.define_singleton_method(:fetch, original_fetch)
    end
    assert_not slot.locked?, "an exception must release the slot"

    with_scrape_failure(:timeout) do
      post recipe_imports_url, params: { url: "https://example.com/recipes/again" }
    end
    assert_includes flash[:alert], "took too long", "the next import must be allowed to run"
  end

  # @card-34.5
  test "each scrape failure explains what the user can do about it" do
    {
      blocked_by_site: "blocks automatic recipe imports",
      timeout: "took too long to respond",
      not_found: "no longer exists",
      site_error: "having trouble right now",
      unparseable: "couldn't find a recipe on that page"
    }.each do |error, expected|
      with_scrape_failure(error) do
        assert_no_difference "Recipe.count" do
          post recipe_imports_url, params: { url: "https://example.com/recipes/#{error}" }
        end

        assert_redirected_to new_recipe_import_url
        assert_includes flash[:alert], expected, "#{error} needs its own message"
      end
    end
  end

  private

  # The scraper calls the fetcher with its defaults, so shorten the deadline at that call.
  def with_fetch_timeout(seconds)
    original = SafeHttpFetcher.method(:get_response)
    SafeHttpFetcher.define_singleton_method(:get_response) do |url, headers: {}, **|
      original.call(url, headers: headers, timeout: seconds)
    end
    yield
  ensure
    SafeHttpFetcher.define_singleton_method(:get_response, original)
  end

  def with_scrape_failure(error)
    original_fetch = RecipeScraper.method(:fetch)
    RecipeScraper.define_singleton_method(:fetch) { |_url| RecipeScraper::Result.new(error: error) }
    yield
  ensure
    RecipeScraper.define_singleton_method(:fetch, original_fetch)
  end
end
