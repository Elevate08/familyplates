class RecipeImportsController < ApplicationController
  def new
  end

  def create
    url = params[:url].to_s.strip
    if url.blank?
      redirect_to new_recipe_import_path, alert: "Please enter a valid recipe web link."
      return
    end

    data = RecipeScraper.call(url)
    if data.nil?
      redirect_to new_recipe_import_path, alert: "Could not fetch recipe from that web address. Please check the link or add manually."
      return
    end

    @recipe = current_household.recipes.build(
      title: data[:title].presence || "Imported Recipe",
      description: data[:description],
      prep_time: data[:prep_time] || 15,
      cook_time: data[:cook_time] || 20,
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
        aisle_category: ing[:aisle_category] || "Other"
      )
    end

    if @recipe.recipe_ingredients.empty?
      5.times { @recipe.recipe_ingredients.build }
    end

    render "recipes/new"
  end
end
