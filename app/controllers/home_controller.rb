class HomeController < ApplicationController
  allow_unauthenticated_access only: [ :index ]

  def index
    if current_family_member.present?
      # Open to signed-out visitors, so the entitlement check is skipped above;
      # finding this week's plan creates one, which a household without
      # access must not do.
      ensure_household_entitled!
      return if performed?

      meal_plan = current_household.current_meal_plan
      redirect_to meal_plan_path(meal_plan)
    elsif (FamilyPlates.config.require_login || FamilyPlates.config.hosted?) && current_user.nil?
      redirect_to new_session_path
    elsif FamilyPlates.config.hosted? && current_user.present? && current_user.households.empty?
      redirect_to new_signup_path
    else
      redirect_to select_profile_path
    end
  end
end
