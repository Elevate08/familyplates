require "application_system_test_case"

# The waiting page reloads itself while RecipeImportJob fetches the page. Request
# tests see the meta tag; only a browser shows that the reload really happens
# and lands on the saved recipe's edit page or the error without anyone touching it.
class RecipeImportTest < ApplicationSystemTestCase
  # System tests otherwise run jobs on the async adapter, in the background and
  # against the real scraper. This one decides when the import's job runs.
  include ActiveJob::TestHelper

  setup do
    sign_in_as(family_members(:one))
  end

  teardown do
    RecipeScraper.define_singleton_method(:fetch, @original_fetch) if @original_fetch
  end

  test "the waiting page opens the saved recipe by itself when the import finishes" do
    start_import("https://example.com/recipes/browser-tacos")

    assert_text "Importing your recipe"
    assert_current_path %r{\A/recipe_imports/[\h-]+\z}

    finish_import RecipeScraper::Result.new(recipe: { title: "Browser Tacos", servings: 4, ingredients: [] })

    assert_text "Imported \"Browser Tacos\" into your recipe box", wait: 10
    assert_current_path %r{\A/recipes/\d+/edit\z}
    assert_selector "input[name='recipe[title]'][value='Browser Tacos']"
    assert_equal 1, Recipe.where(title: "Browser Tacos").count
  end

  test "the waiting page shows the error by itself when the import fails" do
    start_import("https://example.com/recipes/browser-timeout")

    assert_text "Importing your recipe"

    finish_import RecipeScraper::Result.new(error: :timeout)

    assert_text RecipeImport::FAILURE_MESSAGES[:timeout], wait: 10
    assert_current_path new_recipe_import_path
  end

  private

  def start_import(url)
    visit new_recipe_import_path
    fill_in "Recipe Web Address (URL)", with: url
    click_on "Extract & Import Recipe"
  end

  # Runs the queued job now, the way a worker would, with the scraper answering `result`.
  def finish_import(result)
    @original_fetch = RecipeScraper.method(:fetch)
    RecipeScraper.define_singleton_method(:fetch) { |_url| result }
    perform_enqueued_jobs
  end
end
