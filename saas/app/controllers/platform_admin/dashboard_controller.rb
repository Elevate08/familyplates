module PlatformAdmin
  class DashboardController < BaseController
    def index
      @households_count = Household.count
      @users_count = User.count
      @recent_households = Household.order(created_at: :desc, id: :desc).limit(5)
    end
  end
end
