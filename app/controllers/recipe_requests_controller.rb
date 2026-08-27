class RecipeRequestsController < ApplicationController
  before_action :set_recipe

  def create
    week = Date.current.beginning_of_week
    @recipe_request = @recipe.recipe_requests.find_or_initialize_by(
      family_member: current_family_member,
      week_start_date: week
    )
    @recipe_request.save

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: @recipe, notice: "Added to your cravings for this week!" }
    end
  end

  def destroy
    week = Date.current.beginning_of_week
    @recipe_request = @recipe.recipe_requests.find_by(
      family_member: current_family_member,
      week_start_date: week
    )
    @recipe_request&.destroy

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: @recipe, notice: "Removed from cravings." }
    end
  end

  private

  def set_recipe
    @recipe = current_household.recipes.find(params[:recipe_id])
  end
end
