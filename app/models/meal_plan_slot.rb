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

  # Moving a slot can displace whatever already occupies the destination. Both
  # halves have to be one unit of work: the controller used to destroy the
  # occupant and *then* attempt the update, outside any transaction, so a
  # validation failure on the second half left the destination permanently gone
  # and the source still sitting where it started.
  #
  # Returns true on success, false with errors populated on failure - the same
  # contract as #update, so callers read the same way.
  def move(attributes, household:)
    target_date = self.class.parse_date(attributes[:date]) || date
    target_meal_type = attributes[:meal_type].presence || meal_type
    target_plan = household.current_meal_plan(target_date.beginning_of_week)

    self.class.transaction do
      if target_date != date || target_meal_type != meal_type
        target_plan.meal_plan_slots
                   .where(date: target_date, meal_type: target_meal_type)
                   .where.not(id: id)
                   .find_each(&:destroy!)
      end

      update!(attributes.merge(
        date: target_date,
        meal_type: target_meal_type,
        meal_plan_id: target_plan.id
      ))
    end

    true
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed
    false
  rescue ActiveRecord::InvalidForeignKey
    # A recipe or cook id that does not exist. The transaction has rolled the
    # displaced slot back; report it as a validation failure rather than a 500.
    errors.add(:base, "That recipe or cook no longer exists.")
    false
  end

  def self.parse_date(value)
    return value if value.is_a?(Date)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue Date::Error
    nil
  end

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
