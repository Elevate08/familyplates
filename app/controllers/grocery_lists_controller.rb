class GroceryListsController < ApplicationController
  def show
    if params[:meal_plan_id].present? && params[:meal_plan_id] != "current"
      @meal_plan = current_household.meal_plans.find(params[:meal_plan_id])
    else
      @meal_plan = current_household.current_meal_plan
    end

    @aggregation = IngredientAggregator.call(@meal_plan)
    @aisles = @aggregation[:aisles]
    @total_shopping_count = @aggregation[:total_shopping_count]
    @total_pantry_count = @aggregation[:total_pantry_count]
  end
end
