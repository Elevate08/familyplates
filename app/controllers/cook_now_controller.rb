# One button that answers "what am I cooking?" from the clock and the meal plan,
# so the kitchen display does not have to be navigated to the right recipe by
# someone with flour on their hands.
class CookNowController < ApplicationController
  def show
    at = Time.current
    slot = MealPlanSlot.cooking_now(current_household, at: at) ||
           MealPlanSlot.next_planned(current_household, at: at)

    return redirect_to cook_recipe_path(slot.recipe) if slot

    # Nothing to cook today. Rather than bounce back to the plan, say so and
    # offer what is coming up. A day of leftovers is planned, just not cooked,
    # so it is named as such instead of called empty.
    @upcoming = MealPlanSlot.upcoming_planned(current_household, at: at)
    @leftovers_today = current_household.meal_plan_slots.leftovers
                                        .includes(:recipe)
                                        .where(date: household_today)
                                        .sort_by { |slot| MealPlanSlot.meal_type_rank(slot.meal_type) }
    render layout: "cook"
  end
end
