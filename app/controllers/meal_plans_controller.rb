class MealPlansController < ApplicationController
  before_action :set_meal_plan, only: %i[show print]

  def index
    week = params[:week].present? ? Date.parse(params[:week]).beginning_of_week : Date.current.beginning_of_week
    @meal_plan = current_household.current_meal_plan(week)
    redirect_to meal_plan_path(@meal_plan, view: params[:view], month: params[:month])
  end

  def show
    @view = params[:view] || "week"
    @week_start = @meal_plan.week_start_date
    @prev_week = @week_start - 7.days
    @next_week = @week_start + 7.days

    @recipes = current_household.recipes.alphabetical
    @cravings = current_household.recipes.joins(:recipe_requests)
                                 .where(recipe_requests: { week_start_date: @week_start })
                                 .distinct

    @family_members = current_household.family_members.order(:name)

    if @view == "month"
      @month_date = (params[:month].present? ? Date.parse(params[:month]) : @week_start).beginning_of_month
      @month_start = @month_date.beginning_of_week
      @month_end = @month_date.end_of_month.end_of_week
      @month_days = (@month_start..@month_end).to_a
      @prev_month = @month_date.prev_month
      @next_month = @month_date.next_month

      # Preload all slots for the month
      @month_slots_by_date = MealPlanSlot.joins(:meal_plan)
                                         .where(meal_plans: { household_id: current_household.id })
                                         .where(date: @month_start..@month_end)
                                         .includes(:recipe, :family_member)
                                         .group_by { |s| [s.date, s.meal_type] }
    end
  end

  def print
    @view = params[:view] || "week"
    @week_start = @meal_plan.week_start_date

    if @view == "month"
      @month_date = (params[:month].present? ? Date.parse(params[:month]) : @week_start).beginning_of_month
      @month_start = @month_date.beginning_of_week
      @month_end = @month_date.end_of_month.end_of_week
      @month_days = (@month_start..@month_end).to_a

      @month_slots_by_date = MealPlanSlot.joins(:meal_plan)
                                         .where(meal_plans: { household_id: current_household.id })
                                         .where(date: @month_start..@month_end)
                                         .includes(:recipe, :family_member)
                                         .group_by { |s| [s.date, s.meal_type] }
    end

    render layout: "print"
  end

  private

  def set_meal_plan
    @meal_plan = current_household.meal_plans.find(params[:id])
  end
end
