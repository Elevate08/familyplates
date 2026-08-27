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
      @month_start = @month_date.beginning_of_month
      @month_end = @month_date.end_of_month
      @month_days = (@month_start..@month_end).to_a
      @leading_blank_days = @month_start.cwday - 1
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
      @month_start = @month_date.beginning_of_month
      @month_end = @month_date.end_of_month
      @month_days = (@month_start..@month_end).to_a
      @leading_blank_days = @month_start.cwday - 1

      @month_slots_by_date = MealPlanSlot.joins(:meal_plan)
                                         .where(meal_plans: { household_id: current_household.id })
                                         .where(date: @month_start..@month_end)
                                         .includes(:recipe, :family_member)
                                         .group_by { |s| [s.date, s.meal_type] }
    end

    render layout: "print"
  end

  def sync_calendar
    set_meal_plan
    if current_household.google_calendar_enabled? && current_household.google_calendar_id.present?
      service = GoogleCalendarService.new(current_household)
      synced_count = service.sync_meal_plan(@meal_plan)

      respond_to do |format|
        format.json do
          render json: {
            success: true,
            synced_count: synced_count,
            message: "Successfully synced #{synced_count} meal #{'slot'.pluralize(synced_count)} to Google Calendar!"
          }
        end
        format.html { redirect_back fallback_location: meal_plan_path(@meal_plan), notice: "Weekly meal plan synced to Google Calendar! 📅" }
      end
    else
      respond_to do |format|
        format.json do
          render json: {
            success: false,
            error: "Google Calendar sync is not configured yet. Set it up in the Admin Control Center."
          }, status: :unprocessable_entity
        end
        format.html { redirect_back fallback_location: meal_plan_path(@meal_plan), alert: "Google Calendar sync is not configured yet. Set it up in the Admin Control Center." }
      end
    end
  end

  private

  def set_meal_plan
    @meal_plan = current_household.meal_plans.find(params[:id])
  end
end
