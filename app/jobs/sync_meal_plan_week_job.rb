class SyncMealPlanWeekJob < ApplicationJob
  queue_as :default

  def perform(meal_plan_id)
    meal_plan = MealPlan.find_by(id: meal_plan_id)
    return unless meal_plan

    household = meal_plan.household
    return unless household.google_calendar_enabled? && household.google_calendar_id.present?

    service = GoogleCalendarService.new(household)
    service.sync_meal_plan(meal_plan)
  end
end
