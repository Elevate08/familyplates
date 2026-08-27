class HomeController < ApplicationController
  allow_unauthenticated_access only: [:index]

  def index
    if authenticated?
      meal_plan = current_household.current_meal_plan
      redirect_to meal_plan_path(meal_plan)
    else
      render :landing
    end
  end
end
