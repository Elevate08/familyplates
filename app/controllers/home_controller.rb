class HomeController < ApplicationController
  allow_unauthenticated_access only: [:index]

  def index
    if authenticated?
      if current_family_member.nil?
        redirect_to select_profile_path, alert: "Please select who is in the kitchen today."
      else
        meal_plan = current_household.current_meal_plan
        redirect_to meal_plan_path(meal_plan)
      end
    else
      render :landing
    end
  end
end
