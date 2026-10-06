require "test_helper"

class RecipeImportJobTest < ActiveJob::TestCase
  setup do
    @household = households(:one)
    @import = @household.recipe_imports.create!(url: "https://example.com/recipes/tacos", family_member: family_members(:one))
  end

  teardown do
    RecipeScraper.define_singleton_method(:fetch, @original_fetch) if @original_fetch
  end

  test "runs on the imports queue, so a worker can be pointed at it" do
    assert_equal "imports", RecipeImportJob.new.queue_name
  end

  test "fetches the import's url and stores what the scraper found" do
    fetched = []
    stub_scraper do |url|
      fetched << url
      RecipeScraper::Result.new(recipe: { title: "Tacos", servings: 4, ingredients: [ { raw_text: "1 tortilla", name: "Tortilla" } ] })
    end

    RecipeImportJob.perform_now(@import)

    assert_equal [ "https://example.com/recipes/tacos" ], fetched
    @import.reload
    assert @import.succeeded?
    assert_nil @import.error
    assert_equal "Tacos", @import.data["title"]
    assert_equal "Tortilla", @import.data["ingredients"].first["name"]
    assert @import.started_at
    assert @import.finished_at
  end

  test "saves the recipe into the household's recipe box and remembers it" do
    stub_scraper do |url|
      RecipeScraper::Result.new(recipe: { title: "Tacos", servings: 4, source_url: url, instructions: "Fold.",
                                          ingredients: [ { raw_text: "1 tortilla", name: "Tortilla", quantity: 1.0 } ] })
    end

    assert_difference -> { @household.recipes.count }, 1 do
      RecipeImportJob.perform_now(@import)
    end

    recipe = @household.recipes.order(:id).last
    assert_equal recipe.id, @import.reload.recipe_id
    assert_equal "Tacos", recipe.title
    assert_equal "https://example.com/recipes/tacos", recipe.source_url
    assert_equal [ "Tortilla" ], recipe.recipe_ingredients.map(&:name)
  end

  test "does not save a recipe whose title is already in the box" do
    title = " #{recipes(:one).title.upcase} "
    stub_scraper { |_url| RecipeScraper::Result.new(recipe: { title: title, servings: 4 }) }

    assert_no_difference "Recipe.count" do
      RecipeImportJob.perform_now(@import)
    end

    assert @import.reload.succeeded?
    assert_nil @import.recipe_id
  end

  test "does not save a recipe that fails validation, and keeps what was scraped for the form" do
    stub_scraper { |_url| RecipeScraper::Result.new(recipe: { title: "Bad Link", servings: 4, source_url: "ftp://example.com/x" }) }

    assert_no_difference "Recipe.count" do
      RecipeImportJob.perform_now(@import)
    end

    @import.reload
    assert @import.succeeded?
    assert_nil @import.recipe_id
    assert_equal "Bad Link", @import.data["title"]
  end

  test "marks the import running while it fetches" do
    seen = nil
    import = @import
    stub_scraper do |_url|
      seen = import.reload.status
      RecipeScraper::Result.new(recipe: { title: "Tacos" })
    end

    RecipeImportJob.perform_now(@import)

    assert_equal "running", seen
  end

  test "stores each kind of scraper failure" do
    %i[blocked_by_site timeout not_found site_error unreachable unparseable blocked].each do |error|
      import = @household.recipe_imports.create!(url: "https://example.com/recipes/#{error}")
      stub_scraper { |_url| RecipeScraper::Result.new(error: error) }

      RecipeImportJob.perform_now(import)

      import.reload
      assert import.failed?, "#{error} should fail the import"
      assert_equal error.to_s, import.error
      assert_nil import.data
      assert import.finished_at
    end
  end

  test "an unexpected exception fails the import and still surfaces" do
    stub_scraper { |_url| raise ArgumentError, "bug in the scraper" }

    assert_raises(ArgumentError) { RecipeImportJob.perform_now(@import) }

    @import.reload
    assert @import.failed?
    assert_equal "failed", @import.error
    assert @import.finished_at
  end

  test "does not fetch again for an import that already ran" do
    @import.update!(status: "succeeded", data: { title: "Done" })
    stub_scraper { |_url| raise "must not fetch" }

    RecipeImportJob.perform_now(@import)

    assert_equal "Done", @import.reload.data["title"]
  end

  test "is dropped quietly when the import was deleted before it ran" do
    job = RecipeImportJob.new(@import)
    serialized = job.serialize
    @import.destroy!

    assert_nothing_raised { ActiveJob::Base.execute(serialized) }
  end

  test "is not retried, because a second fetch of a hostile page is not wanted" do
    stub_scraper { |_url| raise "boom" }

    assert_no_enqueued_jobs do
      assert_raises(RuntimeError) { RecipeImportJob.perform_now(@import) }
    end
  end

  test "limits concurrency to one import at a time, keyed by household" do
    other_import = @household.recipe_imports.create!(url: "https://example.com/recipes/second")
    foreign_import = households(:two).recipe_imports.create!(url: "https://example.com/recipes/foreign")

    assert_equal 1, RecipeImportJob.concurrency_limit
    assert_equal RecipeImportJob.new(@import).concurrency_key, RecipeImportJob.new(other_import).concurrency_key
    assert_not_equal RecipeImportJob.new(@import).concurrency_key, RecipeImportJob.new(foreign_import).concurrency_key
    assert_includes RecipeImportJob.new(@import).concurrency_key, @household.id
  end

  private

  def stub_scraper(&fetch)
    @original_fetch ||= RecipeScraper.method(:fetch)
    RecipeScraper.define_singleton_method(:fetch, &fetch)
  end
end
