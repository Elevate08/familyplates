class RecipeImportsController < ApplicationController
  # Starting an import costs the web process nothing, so what is left to bound is how
  # much a household can queue. Counted per household, in the login-throttling store.
  RATE_LIMIT = 10
  RATE_LIMIT_WINDOW = 5.minutes
  RATE_LIMIT_ALERT = "You've started a lot of imports in a short time. Please wait a few minutes and try again.".freeze

  def new
  end

  # The page is fetched, and the recipe saved, by RecipeImportJob, not in this
  # request: a slow or hostile site must not hold a web thread. The person waits on #show.
  def create
    url = params[:url].to_s.strip
    if url.blank?
      redirect_to new_recipe_import_path, alert: "Please enter a valid recipe web link."
      return
    end

    existing_by_url = current_household.recipes.find_by(source_url: url)
    if existing_by_url
      redirect_to existing_by_url, alert: "ℹ️ This recipe link is already saved as \"#{existing_by_url.title}\" in your recipe box."
      return
    end

    if rate_limited?
      Rails.logger.warn("[import] rate_limited household_id=#{current_household.id}")
      redirect_to new_recipe_import_path, alert: RATE_LIMIT_ALERT
      return
    end

    import = current_household.recipe_imports.create!(url: url, family_member: current_family_member)
    RecipeImportJob.perform_later(import)
    redirect_to recipe_import_path(import)
  end

  # The waiting page, which reloads itself until the job is done. Then wherever
  # the import used to end: the saved recipe, an existing recipe with that title,
  # the pre-filled form when it could not be saved, or the reason it failed.
  def show
    @import = current_household.recipe_imports.find(params[:id])
    @import.stall! if @import.stalled?

    if @import.failed?
      redirect_to new_recipe_import_path, alert: @import.failure_message
    elsif @import.succeeded?
      show_import_result
    end
  end

  private

  # Counted after the blank and duplicate-link checks, so only an import that is
  # about to be queued uses up the allowance.
  def rate_limited?
    key = "rate-limit:recipe_imports:#{current_household.id}"
    count = LoginThrottling.store.increment(key, 1, expires_in: RATE_LIMIT_WINDOW)
    count.present? && count > RATE_LIMIT
  end

  def show_import_result
    if @import.recipe_id
      redirect_to_saved_recipe
      return
    end

    existing_by_title = @import.existing_recipe_with_title
    if existing_by_title
      redirect_to existing_by_title, alert: "ℹ️ A recipe titled \"#{existing_by_title.title}\" is already in your recipe box."
      return
    end

    render_unsaved_recipe
  end

  def redirect_to_saved_recipe
    recipe = current_household.recipes.find_by(id: @import.recipe_id)
    if recipe.nil? # deleted since the import
      redirect_to recipes_path
      return
    end

    target_path = current_family_member&.admin? ? edit_recipe_path(recipe) : recipe_path(recipe)
    redirect_to target_path, notice: "🎉 Imported \"#{recipe.title}\" into your recipe box!"
  end

  # The job could not save the recipe: open the form with the scraped values and the errors.
  def render_unsaved_recipe
    @recipe = @import.build_recipe
    @recipe.valid?
    5.times { @recipe.recipe_ingredients.build } if @recipe.recipe_ingredients.empty?

    # recipes/new needs the ingredient catalogue; without it the view queries for it inline.
    set_available_ingredients
    render "recipes/new", status: @recipe.errors.any? ? :unprocessable_entity : :ok
  end

  def set_available_ingredients
    @available_ingredients = IngredientAisleMapping.available_ingredients_with_aisles(current_household)
    @available_units = RecipeIngredient.available_units(current_household)
    @available_tags = current_household.recipes.pluck(:tags).compact_blank.flat_map { |t| t.split(",").map(&:strip) }.uniq.sort
  end
end
