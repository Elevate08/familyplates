class RecipeImportsController < ApplicationController
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

    data = RecipeScraper.call(url)
    if data.nil?
      redirect_to new_recipe_import_path, alert: "Could not fetch recipe from that web address. Please check the link or add manually."
      return
    end

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
        aisle_category: ing[:aisle_category] || "Other"
      )
    end

    if @recipe.save
      redirect_to @recipe, notice: "🎉 Successfully imported \"#{@recipe.title}\" into your recipe box!"
    else
      if @recipe.recipe_ingredients.empty?
        5.times { @recipe.recipe_ingredients.build }
      end
      render "recipes/new", status: :unprocessable_entity
    end
  end
end
