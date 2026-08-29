module Admin
  class DashboardController < BaseController
    def index
      @household = current_household
      @family_members = @household.family_members.order(:created_at)
      @recipes_count = @household.recipes.count
      @meal_plans_count = @household.meal_plans.count
    end
  end
end
