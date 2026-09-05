# One button that answers "what am I cooking?" from the clock and the meal plan,
# so the kitchen display does not have to be navigated to the right recipe by
# someone with flour on their hands.
class CookNowController < ApplicationController
  def show
    at = Time.current
    slot = MealPlanSlot.cooking_now(current_household, at: at) ||
           MealPlanSlot.next_planned(current_household, at: at)

    return redirect_to cook_recipe_path(slot.recipe) if slot

    # Nothing planned for today. Rather than bounce back to the plan, say so and
    # offer what is coming up.
    @upcoming = MealPlanSlot.upcoming_planned(current_household, at: at)
    render layout: "cook"
  end
end
