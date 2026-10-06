class RecipeImportsController < ApplicationController
  def new
  end

  # The page is fetched by RecipeImportJob, not in this request: a slow or hostile
  # site must not hold a web thread. The person waits on #show.
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

    import = current_household.recipe_imports.create!(url: url, family_member: current_family_member)
    RecipeImportJob.perform_later(import)
    redirect_to recipe_import_path(import)
  end

  # The waiting page, which reloads itself until the job is done. Then the
  # pre-filled recipe form, or the reason it failed.
  def show
    @import = current_household.recipe_imports.find(params[:id])

    if @import.failed? || @import.stalled?
      redirect_to new_recipe_import_path, alert: @import.failure_message
    elsif @import.succeeded?
      show_imported_recipe
    end
  end

  private

  def show_imported_recipe
    data = @import.recipe_data

    existing_by_title = current_household.recipes.where("LOWER(title) = ?", data[:title].to_s.strip.downcase).first
    if existing_by_title
      redirect_to existing_by_title, alert: "ℹ️ A recipe titled \"#{existing_by_title.title}\" is already in your recipe box."
      return
    end

    @recipe = current_household.recipes.build(
      title: data[:title].presence || "Imported Recipe",
      description: data[:description],
      prep_time: data[:prep_time],
      cook_time: data[:cook_time],
      total_time: data[:total_time],
      equipment: data[:equipment],
      servings: data[:servings] || RecipeScraper::DEFAULT_SERVINGS,
      source_url: data[:source_url],
      image_url: data[:image_url],
      instructions: data[:instructions]
    )

    Array(data[:ingredients]).each do |ing|
      @recipe.recipe_ingredients.build(
        raw_text: ing[:raw_text],
        name: ing[:name],
        quantity: ing[:quantity],
        unit: ing[:unit],
        # nil, not "Other" - the model classifies when no aisle is supplied,
        # and cannot tell a scraper default from a user's deliberate choice.
        aisle_category: ing[:aisle_category].presence
      )
    end
    5.times { @recipe.recipe_ingredients.build } if @recipe.recipe_ingredients.empty?

    # recipes/new needs the ingredient catalogue; without it the view queries for it inline.
    set_available_ingredients
    render "recipes/new"
  end

  def set_available_ingredients
    @available_ingredients = IngredientAisleMapping.available_ingredients_with_aisles(current_household)
    @available_units = RecipeIngredient.available_units(current_household)
    @available_tags = current_household.recipes.pluck(:tags).compact_blank.flat_map { |t| t.split(",").map(&:strip) }.uniq.sort
  end
end
