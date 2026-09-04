class HomeController < ApplicationController
  allow_unauthenticated_access only: [ :index ]

  def index
    if current_family_member.present?
      meal_plan = current_household.current_meal_plan
      redirect_to meal_plan_path(meal_plan)
    elsif FamilyPlates.config.require_login && current_user.nil?
      redirect_to new_session_path, alert: "Please sign in to continue."
    else
      redirect_to select_profile_path
    end
  end
end
