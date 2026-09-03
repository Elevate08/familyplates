class HomeController < ApplicationController
  allow_unauthenticated_access only: [ :index ]

  def index
    if current_family_member.present?
      meal_plan = current_household.current_meal_plan
      redirect_to meal_plan_path(meal_plan)
    else
      redirect_to select_profile_path
    end
  end
end
