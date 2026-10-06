require "test_helper"

class RecipeImportsControllerTest < ActionDispatch::IntegrationTest
  include SlowDripHelper

  GENERIC_FAILURE = "Could not fetch recipe from that web address. Please check the link or add manually.".freeze

  setup do
    @admin = family_members(:one)
    sign_in_as(@admin)
  end

  teardown do
    RecipeScraper.define_singleton_method(:fetch, @original_fetch) if @original_fetch
  end

  test "should get new" do
    get new_recipe_import_url
    assert_response :success
  end

  test "should handle blank url" do
    assert_no_difference "RecipeImport.count" do
      post recipe_imports_url, params: { url: "" }
    end
    assert_redirected_to new_recipe_import_url
  end

  test "starting an import queues a job on the imports queue and sends the person to the waiting page" do
    stub_scraper { |_url| raise "the request must not fetch" }

    assert_difference "RecipeImport.count", 1 do
      assert_enqueued_with(job: RecipeImportJob, queue: "imports") do
        post recipe_imports_url, params: { url: "  https://example.com/recipes/tacos  " }
      end
    end

    import = RecipeImport.order(:created_at).last
    assert_redirected_to recipe_import_url(import)
    assert_equal households(:one), import.household
    assert_equal @admin, import.family_member
    assert_equal "https://example.com/recipes/tacos", import.url
    assert import.queued?
  end

  test "the waiting page says the import is in progress and refreshes itself" do
    import = households(:one).recipe_imports.create!(url: "https://example.com/recipes/wait")

    get recipe_import_url(import)
    assert_response :success
    assert_select "meta[http-equiv=refresh][content^='3']", 1
    # Turbo would otherwise merge the tag into the page it is already showing.
    assert_select "meta[name='turbo-visit-control'][content=reload]", 1
    assert_select "a", text: "Back to Recipe Box"
    assert_select "a", text: /Cancel/, count: 0
    assert_select "[role=status]", text: /appear in your recipe box when the import finishes/
    assert_select "[role=status]", text: /Importing/
    assert_select "form[action='#{recipes_path}']", 0

    import.update!(status: "running", started_at: Time.current)
    get recipe_import_url(import)
    assert_response :success
    assert_select "meta[http-equiv=refresh]", 1
  end

  test "a finished import is saved by the job and an organizer lands on its edit page" do
    scraped = french_toast
    stub_scraper { |_url| RecipeScraper::Result.new(recipe: scraped) }

    assert_difference "Recipe.count", 1 do
      import_and_wait("https://www.allrecipes.com/recipe/22389/french-toast-casserole/")
    end

    recipe = Recipe.order(:id).last
    assert_redirected_to edit_recipe_url(recipe)
    assert_includes flash[:notice], "Imported"
    assert_equal households(:one), recipe.household
    assert_equal "French Toast Casserole", recipe.title
    assert_equal "https://www.allrecipes.com/recipe/22389/french-toast-casserole/", recipe.source_url
    assert_equal 6, recipe.servings
    assert_equal 1, recipe.recipe_ingredients.count
    assert_equal "Bread cubes", recipe.recipe_ingredients.first.name
  end

  test "a finished import takes a member to the recipe page, not the organizer's edit page" do
    delete session_url
    sign_in_as(family_members(:two))
    scraped = french_toast
    stub_scraper { |_url| RecipeScraper::Result.new(recipe: scraped) }

    assert_difference "Recipe.count", 1 do
      import_and_wait("https://www.allrecipes.com/recipe/22389/french-toast-casserole/")
    end

    assert_redirected_to recipe_url(Recipe.order(:id).last)
    assert_includes flash[:notice], "Imported"
  end

  test "reloading the page after the import was saved does not save it again" do
    scraped = french_toast
    stub_scraper { |_url| RecipeScraper::Result.new(recipe: scraped) }

    import_and_wait("https://www.allrecipes.com/recipe/22389/french-toast-casserole/")

    assert_no_difference "Recipe.count" do
      get recipe_import_url(RecipeImport.order(:created_at).last)
    end
    assert_redirected_to edit_recipe_url(Recipe.order(:id).last)
  end

  test "an import that cannot be saved opens the pre-filled recipe form with the errors" do
    scraped = french_toast.merge(source_url: "ftp://example.com/not-web")
    stub_scraper { |_url| RecipeScraper::Result.new(recipe: scraped) }

    assert_no_difference "Recipe.count" do
      import_and_wait("https://example.com/recipes/unsaveable")
    end

    assert_response :unprocessable_entity
    assert_select "meta[http-equiv=refresh]", 0
    assert_select "form[action='#{recipes_path}']" do
      assert_select "input[name='recipe[title]'][value='French Toast Casserole']"
      assert_select "input[name='recipe[servings]'][value='6']"
      assert_select "input[name='recipe[recipe_ingredients_attributes][0][name]'][value='Bread cubes']"
      assert_select "input[name='recipe[recipe_ingredients_attributes][0][unit]'][value='cups']"
    end
    assert_select "p", text: /prohibited this recipe from being saved/
  end

  test "an import that cannot be saved and has no ingredients still offers blank ingredient rows" do
    stub_scraper do |_url|
      RecipeScraper::Result.new(recipe: { title: "Plain Page", servings: 4, source_url: "ftp://example.com/x", ingredients: [] })
    end

    assert_no_difference "Recipe.count" do
      import_and_wait("https://example.com/recipes/plain")
    end

    assert_response :unprocessable_entity
    assert_select "input[name='recipe[title]'][value='Plain Page']"
    assert_select "input[name^='recipe[recipe_ingredients_attributes]'][name$='[name]']", minimum: 5
  end

  test "should redirect with alert if recipe URL already imported" do
    recipes(:one).update!(source_url: "https://example.com/existing-tacos")

    assert_no_difference "RecipeImport.count" do
      post recipe_imports_url, params: { url: "https://example.com/existing-tacos" }
    end
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
    stub_scraper { |_url| RecipeScraper::Result.new(recipe: scraped_data) }

    assert_no_difference "Recipe.count" do
      import_and_wait("https://example.com/different-tacos")
    end

    assert_redirected_to recipe_url(recipes(:one))
    assert_includes flash[:alert], "already in your recipe box"
  end

  test "a blocked import URL is refused with the ordinary error and creates nothing" do
    assert_no_difference "Recipe.count" do
      import_and_wait("http://169.254.169.254/latest/meta-data/")
    end

    assert_redirected_to new_recipe_import_url
    assert_equal GENERIC_FAILURE, flash[:alert]
  end

  test "a site that trickles its response is cut off and the import says it timed out" do
    with_slow_drip_server do |url|
      with_fetch_timeout(2) do
        assert_no_difference "Recipe.count" do
          import_and_wait(url)
        end
      end
    end

    assert_redirected_to new_recipe_import_url
    assert_equal RecipeImport::FAILURE_MESSAGES[:timeout], flash[:alert]
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
      stub_scraper { |_url| RecipeScraper::Result.new(error: error) }

      assert_no_difference "Recipe.count" do
        import_and_wait("https://example.com/recipes/#{error}")
      end

      assert_redirected_to new_recipe_import_url
      assert_includes flash[:alert], expected, "#{error} needs its own message"
    end
  end

  test "an import that crashed leaves the person with the ordinary error, not a spinner" do
    stub_scraper { |_url| raise "boom" }

    post recipe_imports_url, params: { url: "https://example.com/recipes/crash" }
    assert_raises(RuntimeError) { perform_enqueued_jobs }

    get recipe_import_url(RecipeImport.order(:created_at).last)
    assert_redirected_to new_recipe_import_url
    assert_equal GENERIC_FAILURE, flash[:alert]
  end

  test "an import nobody picked up for minutes stops claiming progress, and never runs afterwards" do
    import = households(:one).recipe_imports.create!(url: "https://example.com/recipes/stuck", created_at: 10.minutes.ago)
    RecipeImportJob.perform_later(import)

    get recipe_import_url(import)

    assert_redirected_to new_recipe_import_url
    assert_equal RecipeImport::FAILURE_MESSAGES[:busy], flash[:alert]
    assert import.reload.failed?
    assert_equal "busy", import.error

    stub_scraper { |_url| raise "a stalled import must not be fetched" }
    assert_no_difference "Recipe.count" do
      perform_enqueued_jobs
    end
    assert import.reload.failed?
    assert_nil import.recipe_id
  end

  test "an import that has been running for minutes stops claiming progress" do
    import = households(:one).recipe_imports.create!(url: "https://example.com/recipes/dead",
                                                     status: "running", started_at: 10.minutes.ago)

    get recipe_import_url(import)

    assert_redirected_to new_recipe_import_url
    assert_equal RecipeImport::FAILURE_MESSAGES[:busy], flash[:alert]
    assert import.reload.failed?
  end

  test "an import that waited a long time in the queue but only just started is still working" do
    import = households(:one).recipe_imports.create!(url: "https://example.com/recipes/slow-start", created_at: 10.minutes.ago,
                                                     status: "running", started_at: 10.seconds.ago)

    get recipe_import_url(import)

    assert_response :success
    assert import.reload.running?
  end

  test "starting too many imports is refused, and only imports that were queued count" do
    15.times { post recipe_imports_url, params: { url: "" } }
    recipes(:one).update!(source_url: "https://example.com/saved")
    15.times { post recipe_imports_url, params: { url: "https://example.com/saved" } }
    assert_equal 0, RecipeImport.count

    10.times { |n| post recipe_imports_url, params: { url: "https://example.com/recipes/#{n}" } }
    assert_equal 10, RecipeImport.count
    assert_response :redirect

    assert_no_enqueued_jobs only: RecipeImportJob do
      post recipe_imports_url, params: { url: "https://example.com/recipes/eleven" }
    end
    assert_redirected_to new_recipe_import_url
    assert_equal RecipeImportsController::RATE_LIMIT_ALERT, flash[:alert]
    assert_equal 10, RecipeImport.count
  end

  test "another household is not held back by one household's imports" do
    10.times { |n| post recipe_imports_url, params: { url: "https://example.com/recipes/#{n}" } }
    post recipe_imports_url, params: { url: "https://example.com/recipes/eleven" }
    assert_equal RecipeImportsController::RATE_LIMIT_ALERT, flash[:alert]

    neighbour = households(:two).family_members.create!(name: "Miller Kid", role: "member", avatar_color: "#84CC16", avatar_icon: "smile")
    delete session_url
    sign_in_user(User.create!(email: "miller@import.test").tap { |user| neighbour.update!(user: user) })
    sign_in_as(neighbour)

    assert_difference -> { households(:two).recipe_imports.count }, 1 do
      post recipe_imports_url, params: { url: "https://example.com/recipes/miller" }
    end
    assert_redirected_to recipe_import_url(households(:two).recipe_imports.last)
  end

  test "another household's import is not found" do
    other = households(:two).recipe_imports.create!(url: "https://example.com/recipes/theirs", status: "succeeded",
                                                    data: { title: "Miller Secret Casserole" })

    get recipe_import_url(other)

    assert_response :not_found
  end

  test "an unknown import is not found" do
    get recipe_import_url("no-such-import")
    assert_response :not_found
  end

  private

  def french_toast
    {
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
  end

  # Starts an import, runs its job, and opens the page the person would be sent to.
  def import_and_wait(url)
    post recipe_imports_url, params: { url: url }
    perform_enqueued_jobs
    get recipe_import_url(RecipeImport.order(:created_at).last)
  end

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

  # Replaced for the rest of the test; teardown puts the real one back.
  def stub_scraper(&fetch)
    @original_fetch ||= RecipeScraper.method(:fetch)
    RecipeScraper.define_singleton_method(:fetch, &fetch)
  end
end
