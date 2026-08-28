class RecipesController < ApplicationController
  before_action :set_recipe, only: %i[show edit update destroy]

  def index
    @recipes = current_household.recipes.alphabetical

    if params[:query].present?
      q = "%#{params[:query].strip.downcase}%"
      @recipes = @recipes.where("LOWER(title) LIKE ? OR LOWER(tags) LIKE ?", q, q)
    end

    case params[:filter]
    when "requested"
      RecipeRequest.auto_fulfill_passed_slots!
      recipe_ids = current_household.recipes.joins(:recipe_requests)
                                    .where(recipe_requests: { fulfilled_at: nil })
                                    .distinct.pluck(:id)
      @recipes = @recipes.where(id: recipe_ids)
    when "quick"
      @recipes = @recipes.quick
    when "breakfast", "lunch", "dinner"
      @recipes = @recipes.for_meal_type(params[:filter])
    end
  end

  def show
    @week_start = Date.current.beginning_of_week
    @requested_by_current = @recipe.requested_by?(current_family_member, @week_start)
    @total_requests = @recipe.request_count_for_week(@week_start)
  end

  def new
    @recipe = current_household.recipes.build(servings: 4, prep_time: 15, cook_time: 20)
    5.times { @recipe.recipe_ingredients.build }
  end

  def create
    @recipe = current_household.recipes.build(recipe_params)

    if @recipe.save
      redirect_to @recipe, notice: "Recipe \"#{@recipe.title}\" was successfully added to your recipe box!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @recipe.recipe_ingredients.build if @recipe.recipe_ingredients.empty?
  end

  def update
    if @recipe.update(recipe_params)
      redirect_to @recipe, notice: "Recipe updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @recipe.destroy
    redirect_to recipes_path, notice: "Recipe deleted from recipe box."
  end

  def bulk_update
    recipe_ids = Array(params[:recipe_ids]).reject(&:blank?)
    recipes = current_household.recipes.where(id: recipe_ids)

    if recipes.empty?
      redirect_to recipes_path(filter: params[:filter], query: params[:query], view: params[:view]), alert: "No recipes selected."
      return
    end

    # Bulk Meal Types Update
    if params[:update_meal_types].present? || params[:meal_types_mode].present?
      selected_meal_types = Array(params[:meal_types]).reject(&:blank?)
      recipes.each do |recipe|
        recipe.update(meal_types: selected_meal_types.join(","))
      end
    end

    # Bulk Tags Update
    if params[:update_tags].present? || params[:tags_mode].present?
      new_tags = params[:tags].to_s.split(",").map(&:strip).reject(&:blank?)
      recipes.each do |recipe|
        recipe.update(tags: new_tags.join(", "))
      end
    end

    redirect_to recipes_path(filter: params[:filter], query: params[:query], view: params[:view]),
                notice: "✨ Successfully updated #{recipes.count} #{'recipe'.pluralize(recipes.count)}.",
                status: :see_other
  end

  def bulk_destroy
    recipe_ids = Array(params[:recipe_ids]).reject(&:blank?)
    recipes = current_household.recipes.where(id: recipe_ids)

    if recipes.empty?
      redirect_to recipes_path(filter: params[:filter], query: params[:query], view: params[:view]), alert: "No recipes selected.", status: :see_other
      return
    end

    count = recipes.count
    recipes.destroy_all

    redirect_to recipes_path(filter: params[:filter], query: params[:query], view: params[:view]),
                notice: "🗑️ Deleted #{count} #{'recipe'.pluralize(count)} from your recipe box.",
                status: :see_other
  end

  private

  def set_recipe
    @recipe = current_household.recipes.find(params[:id])
  end

  def recipe_params
    cleaned_params = params.require(:recipe).permit(
      :title, :description, :prep_time, :cook_time, :total_time, :equipment, :servings,
      :source_url, :image_url, :image, :instructions, :tags, :meal_types, :yields_leftovers,
      meal_types: [],
      recipe_ingredients_attributes: %i[id name raw_text quantity unit aisle_category _destroy]
    )

    if cleaned_params[:meal_types].is_a?(Array)
      cleaned_params[:meal_types] = cleaned_params[:meal_types].reject(&:blank?).join(",")
    end
    cleaned_params
  end
end
