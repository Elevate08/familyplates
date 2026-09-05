class RecipeImportsController < ApplicationController
  # The failure path renders "recipes/new", which needs the ingredient
  # catalogue. Without this the view fell back to querying for it inline.
  before_action :set_available_ingredients, only: %i[create]

  def new
  end

  def create
    url = params[:url].to_s.strip
    if url.blank?
      redirect_to new_recipe_import_path, alert: "Please enter a valid recipe web link."
      return
    end

    # Check if a recipe with this exact URL already exists in household
    existing_by_url = current_household.recipes.find_by(source_url: url)
    if existing_by_url
      redirect_to existing_by_url, alert: "ℹ️ This recipe link is already saved as \"#{existing_by_url.title}\" in your recipe box."
      return
    end

    result = RecipeScraper.fetch(url)
    if !result.success?
      redirect_to new_recipe_import_path, alert: import_failure_message(result.error)
      return
    end

    data = result.recipe

    # Check if a recipe with this title already exists in household
    existing_by_title = current_household.recipes.where("LOWER(title) = ?", data[:title].to_s.strip.downcase).first
    if existing_by_title
      redirect_to existing_by_title, alert: "ℹ️ A recipe titled \"#{existing_by_title.title}\" is already in your recipe box."
      return
    end

    @recipe = current_household.recipes.build(
      title: data[:title].presence || "Imported Recipe",
      description: data[:description],
      prep_time: data[:prep_time] || 15,
      cook_time: data[:cook_time] || 20,
      total_time: data[:total_time],
      equipment: data[:equipment],
      servings: data[:servings] || 4,
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

    saved = RecipeIngredient.without_aisle_sync { @recipe.save }
    @recipe.resync_aisle_mappings! if saved

    if saved
      target_path = current_family_member&.admin? ? edit_recipe_path(@recipe) : recipe_path(@recipe)
      redirect_to target_path, notice: "🎉 Imported \"#{@recipe.title}\" into your recipe box!"
    else
      if @recipe.recipe_ingredients.empty?
        5.times { @recipe.recipe_ingredients.build }
      end
      render "recipes/new", status: :unprocessable_entity
    end
  end

  private

  # "Could not fetch recipe" covered a site refusing bots, a dead link, and a
  # page with no recipe on it alike, which left the user with nothing to act on.
  IMPORT_FAILURE_MESSAGES = {
    blocked_by_site: "That site blocks automatic recipe imports. Try copying the recipe in manually, or import it from another site.",
    timeout: "That site took too long to respond. Please try again in a moment, or add the recipe manually.",
    not_found: "That recipe page no longer exists. Please double-check the link.",
    site_error: "That site is having trouble right now. Please try again later, or add the recipe manually.",
    unparseable: "We couldn't find a recipe on that page. Make sure the link points at the recipe itself, or add it manually."
    # :blocked (egress policy) deliberately has no entry: an address this server
    # is not allowed to reach must look exactly like any other bad link, or the
    # message becomes a probe for what is reachable from inside the network.
  }.freeze

  DEFAULT_IMPORT_FAILURE_MESSAGE = "Could not fetch recipe from that web address. Please check the link or add manually.".freeze

  def import_failure_message(error)
    IMPORT_FAILURE_MESSAGES.fetch(error, DEFAULT_IMPORT_FAILURE_MESSAGE)
  end

  def set_available_ingredients
    @available_ingredients = IngredientAisleMapping.available_ingredients_with_aisles(current_household)
    @available_units = RecipeIngredient.available_units(current_household)
    @available_tags = current_household.recipes.pluck(:tags).compact_blank.flat_map { |t| t.split(",").map(&:strip) }.uniq.sort
  end
end
