module PlatformAdmin
  class HouseholdsController < BaseController
    PAGE_SIZE = 50

    def index
      @search = params[:search].to_s.strip
      @households = filtered_households
        .includes(:family_members, :users)
        .order(created_at: :desc, id: :desc)
        .limit(PAGE_SIZE)
    end

    def show
      @household = Household.includes(:family_members, :users).find(params[:id])
      @family_members = @household.family_members.order(:created_at, :id)
      @recipes_count = @household.recipes.count
      @meal_plans_count = @household.meal_plans.count
      @pantry_items_count = @household.pantry_items.count
    end

    def suspend
      @household = Household.find(params[:id])
      @household.update!(suspended_at: Time.current, suspension_reason: params[:reason].to_s.strip.presence)
      redirect_to platform_admin_household_path(@household), notice: "Household suspended."
    end

    def restore
      @household = Household.find(params[:id])
      @household.update!(suspended_at: nil, suspension_reason: nil)
      redirect_to platform_admin_household_path(@household), notice: "Household restored."
    end

    private

    def filtered_households
      return Household.all if @search.blank?

      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@search)}%"
      Household.left_joins(family_members: :user)
        .where("households.name LIKE :pattern OR users.email LIKE :pattern OR family_members.name LIKE :pattern", pattern: pattern)
        .distinct
    end
  end
end
