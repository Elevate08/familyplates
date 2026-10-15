class GroceryListsController < ApplicationController
  def show
    @range = GroceryRange.from_params(params[:from], params[:to], today: household_today)

    @aggregation = IngredientAggregator.call(current_household, @range.to_range)
    @aisles = @aggregation[:aisles]
    @total_shopping_count = @aggregation[:total_shopping_count]
    @total_pantry_count = @aggregation[:total_pantry_count]
    @total_restock_count = @aggregation[:total_restock_count]
    @meal_count = @aggregation[:meal_count]
  end

  # The old per-plan address: opens the list for that plan's week.
  def plan
    return redirect_to(grocery_list_path) if params[:meal_plan_id] == "current"

    meal_plan = current_household.meal_plans.find_by(number: params[:meal_plan_id]) ||
                current_household.meal_plans.find_by(id: params[:meal_plan_id])
    raise ActiveRecord::RecordNotFound, "Couldn't find MealPlan with 'id'=#{params[:meal_plan_id]}" unless meal_plan

    week = meal_plan.week_start_date
    redirect_to grocery_list_path(from: week.iso8601, to: (week + 6.days).iso8601)
  end
end
