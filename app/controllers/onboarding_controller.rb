class OnboardingController < ApplicationController
  before_action :load_starter_recipes, only: %i[recipes save_recipes]

  def recipes
    @selected_recipe_ids = @starter_recipes.map { |r| r["id"] }
  end

  def save_recipes
    selected_ids = Array(params[:recipe_ids]).map(&:to_s)
    
    ActiveRecord::Base.transaction do
      @starter_recipes.each do |starter|
        next unless selected_ids.include?(starter["id"])

        recipe = current_household.recipes.create!(
          title: starter["title"],
          description: starter["description"],
          prep_time: starter["prep_time"],
          cook_time: starter["cook_time"],
          servings: starter["servings"] || 4,
          image_url: starter["image_url"],
          instructions: starter["instructions"],
          tags: Array(starter["tags"]).join(", ")
        )

        Array(starter["ingredients"]).each do |ing|
          recipe.recipe_ingredients.create!(
            raw_text: ing["raw_text"],
            name: ing["name"],
            quantity: ing["quantity"],
            unit: ing["unit"],
            aisle_category: ing["aisle_category"] || "Other"
          )
        end
      end
    end

    redirect_to onboarding_pantry_path, notice: "Great picks! Now let's confirm your household pantry staples."
  end

  def pantry
    @default_staples = PantryItem::DEFAULT_STAPLES
  end

  def save_pantry
    selected_staple_names = Array(params[:staple_names]).map(&:to_s)

    ActiveRecord::Base.transaction do
      PantryItem::DEFAULT_STAPLES.each do |staple|
        is_selected = selected_staple_names.include?(staple[:name])
        current_household.pantry_items.find_or_create_by!(name: staple[:name]) do |item|
          item.aisle_category = staple[:aisle_category]
          item.is_staple = is_selected
        end
      end
    end

    redirect_to root_path, notice: "🎉 Your kitchen is ready! Start planning your first weekly meals."
  end

  private

  def load_starter_recipes
    config = YAML.load_file(Rails.root.join("config/starter_recipes.yml"))
    @starter_recipes = config["starter_recipes"] || []
  end
end
