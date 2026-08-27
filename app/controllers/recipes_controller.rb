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
      week = Date.current.beginning_of_week
      recipe_ids = current_household.recipes.joins(:recipe_requests)
                                    .where(recipe_requests: { week_start_date: week })
                                    .distinct.pluck(:id)
      @recipes = @recipes.where(id: recipe_ids)
    when "quick"
      @recipes = @recipes.quick
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

  private

  def set_recipe
    @recipe = current_household.recipes.find(params[:id])
  end

  def recipe_params
    params.require(:recipe).permit(
      :title, :description, :prep_time, :cook_time, :servings,
      :source_url, :image_url, :instructions, :tags,
      recipe_ingredients_attributes: %i[id name raw_text quantity unit aisle_category _destroy]
    )
  end
end
