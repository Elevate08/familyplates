class GroceryListsController < ApplicationController
  def show
    if params[:meal_plan_id].present? && params[:meal_plan_id] != "current"
      @meal_plan = current_household.meal_plans.find_by(number: params[:meal_plan_id]) || current_household.meal_plans.find_by(id: params[:meal_plan_id])
      raise ActiveRecord::RecordNotFound, "Couldn't find MealPlan with 'id'=#{params[:meal_plan_id]}" unless @meal_plan
    else
      @meal_plan = current_household.current_meal_plan
    end

    @aggregation = IngredientAggregator.call(@meal_plan)
    @aisles = @aggregation[:aisles]
    @total_shopping_count = @aggregation[:total_shopping_count]
    @total_pantry_count = @aggregation[:total_pantry_count]
    @total_restock_count = @aggregation[:total_restock_count]
  end
end
