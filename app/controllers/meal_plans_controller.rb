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
    RecipeRequest.auto_fulfill_passed_slots!(current_household)
    @cravings = current_household.recipes.joins(:recipe_requests)
                                 .where(recipe_requests: { fulfilled_at: nil })
                                 .distinct

    @family_members = current_household.family_members.order(:name)

    if @view == "month"
      @month_date = resolve_month_date(@week_start)
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
                                         .group_by { |s| [ s.date, s.meal_type ] }
    end
  end

  def print
    @view = params[:view] || "week"
    @week_start = @meal_plan.week_start_date

    if @view == "month"
      @month_date = resolve_month_date(@week_start)
      @month_start = @month_date.beginning_of_month
      @month_end = @month_date.end_of_month
      @month_days = (@month_start..@month_end).to_a
      @leading_blank_days = @month_start.cwday - 1

      @month_slots_by_date = MealPlanSlot.joins(:meal_plan)
                                         .where(meal_plans: { household_id: current_household.id })
                                         .where(date: @month_start..@month_end)
                                         .includes(:recipe, :family_member)
                                         .group_by { |s| [ s.date, s.meal_type ] }
    end

    render layout: "print"
  end

  private

  def set_meal_plan
    @meal_plan = current_household.meal_plans.find_by(number: params[:id]) || current_household.meal_plans.find_by(id: params[:id])
    raise ActiveRecord::RecordNotFound, "Couldn't find MealPlan with 'id'=#{params[:id]}" unless @meal_plan
  end

  # The month shown by the calendar and its print-out. An explicit month always
  # wins; otherwise we derive it from the week being planned.
  def resolve_month_date(week_start)
    return Date.parse(params[:month]).beginning_of_month if params[:month].present?

    default_month_for(week_start)
  end

  # A week can straddle two months, so "the month of the week" is ambiguous.
  # We show whichever month holds most of the week: the 4th day always lands in
  # the month owning 4 or more of the 7 days, whichever side of the split it is
  # on. Anchoring on the week's first day instead hides the tail of the week
  # whenever a week starts near the end of a month.
  def default_month_for(week_start)
    (week_start + 3.days).beginning_of_month
  end
end
