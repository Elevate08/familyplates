class MealPlanSlot < ApplicationRecord
  belongs_to :meal_plan
  belongs_to :recipe, optional: true
  belongs_to :family_member, optional: true

  MEAL_TYPES = %w[breakfast lunch dinner].freeze

  validates :date, presence: true
  validates :meal_type, inclusion: { in: MEAL_TYPES }
  validates :meal_type, uniqueness: { scope: [ :meal_plan_id, :date ], message: "slot already exists for this date and meal type" }

  scope :leftovers, -> { where(is_leftover: true) }
  scope :fresh_meals, -> { where(is_leftover: false) }

  after_commit :sync_to_google_calendar, on: %i[create update]
  after_destroy_commit :delete_from_google_calendar
  after_save :fulfill_recipe_requests_if_passed

  def display_title
    recipe&.title.presence || custom_title.presence || "No Meal Planned"
  end

  def cook_name
    family_member&.name
  end

  private

  def sync_to_google_calendar
    return unless meal_plan&.household&.google_calendar_enabled?

    if display_title == "No Meal Planned" && google_event_id.present?
      SyncMealPlanSlotJob.perform_later(id, "delete", google_event_id, meal_plan.household_id)
    elsif display_title != "No Meal Planned"
      SyncMealPlanSlotJob.perform_later(id, "upsert", google_event_id, meal_plan.household_id)
    end
  end

  def delete_from_google_calendar
    return unless google_event_id.present? && meal_plan&.household&.google_calendar_enabled?

    SyncMealPlanSlotJob.perform_later(nil, "delete", google_event_id, meal_plan.household_id)
  end

  def fulfill_recipe_requests_if_passed
    return unless recipe.present? && date.present? && date <= Date.current

    recipe.recipe_requests.active.where("week_start_date <= ? OR created_at <= ?", date, date.end_of_day).find_each do |req|
      req.update_columns(fulfilled_at: date.to_time)
    end
  end
end
