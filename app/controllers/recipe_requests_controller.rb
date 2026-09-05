class RecipeRequestsController < ApplicationController
  before_action :set_recipe

  def create
    RecipeRequest.auto_fulfill_passed_slots!(current_household)
    @recipe_request = @recipe.recipe_requests.find_or_initialize_by(
      family_member: current_family_member,
      fulfilled_at: nil
    )
    @recipe_request.week_start_date ||= household_today.beginning_of_week
    @recipe_request.save
    @recipe.reload

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: @recipe, notice: "Added to your cravings!" }
    end
  end

  def destroy
    @recipe_request = @recipe.recipe_requests.active.find_by(
      family_member: current_family_member
    )
    @recipe_request&.destroy
    @recipe.reload

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_back fallback_location: @recipe, notice: "Removed from cravings." }
    end
  end

  private

  def set_recipe
    @recipe = current_household.recipes.find_by(number: params[:recipe_id]) || current_household.recipes.find_by(id: params[:recipe_id])
    raise ActiveRecord::RecordNotFound, "Couldn't find Recipe with 'id'=#{params[:recipe_id]}" unless @recipe
  end
end
