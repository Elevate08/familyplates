class MealPlanSlot < ApplicationRecord
  belongs_to :meal_plan
  belongs_to :recipe, optional: true
  belongs_to :family_member, optional: true
  belongs_to :leftover_source_slot, class_name: "MealPlanSlot", optional: true
  has_many :leftover_slots, class_name: "MealPlanSlot", foreign_key: :leftover_source_slot_id, dependent: :nullify

  delegate :household, to: :meal_plan

  MEAL_TYPES = %w[breakfast lunch dinner].freeze

  # Fallbacks for a household row that predates the meal-time columns; the
  # columns themselves default to these same values.
  DEFAULT_MEAL_TIMES = { "breakfast" => "08:00", "lunch" => "12:30", "dinner" => "18:00" }.freeze

  # Cooking starts before the meal is served and often runs past it, so "which
  # meal is being made right now" is a window around the serving time, not the
  # instant itself. Two hours ahead covers a roast going in; ninety minutes past
  # covers a dinner that ran late.
  COOKING_LEAD = 2.hours
  COOKING_GRACE = 90.minutes

  validates :date, presence: true
  validates :meal_type, inclusion: { in: MEAL_TYPES }
  validates :meal_type, uniqueness: { scope: [ :meal_plan_id, :date ], message: "slot already exists for this date and meal type" }
  validate :leftover_source_cannot_be_self
  before_validation :normalize_blank_attributes

  scope :leftovers, -> { where(is_leftover: true) }
  scope :fresh_meals, -> { where(is_leftover: false) }
  scope :with_recipe, -> { where.not(recipe_id: nil) }

  after_save :fulfill_recipe_requests_if_passed

  # When this meal is served: the slot's own time if it has one, otherwise the
  # household's time for that meal. The calendar feed reads the same two fields,
  # so a household that has set its dinner hour gets it honoured in both places.
  #
  # Built in the household's zone, not the server's. "Dinner at 6pm" means six
  # in that kitchen; on a UTC server it would otherwise mean six in Greenwich,
  # which is early afternoon in Chicago and the following morning in Sydney.
  def scheduled_at
    time = scheduled_time.presence || household_meal_time
    hour, minute = time.to_s.split(":").map(&:to_i)

    household.time_zone_object.local(date.year, date.month, date.day, hour.to_i, minute.to_i, 0)
  end

  def cooking_window
    (scheduled_at - COOKING_LEAD)..(scheduled_at + COOKING_GRACE)
  end

  def cooking_now?(at = Time.current)
    cooking_window.cover?(at)
  end

  # The meal someone standing in the kitchen right now is most likely making:
  # of the planned meals whose cooking window is open, the one due soonest.
  def self.cooking_now(household, at: Time.current)
    around(household, at).select { |slot| slot.cooking_now?(at) }
                         .min_by { |slot| (slot.scheduled_at - at).abs }
  end

  # What to offer when no window is open. Today's nearest planned meal, with one
  # still ahead beating one already served - at 3pm that is tonight's dinner, not
  # this morning's breakfast.
  def self.next_planned(household, at: Time.current)
    on_date = local_date(household, at)
    today = around(household, at).select { |slot| slot.date == on_date }
    upcoming = today.select { |slot| slot.scheduled_at >= at }

    (upcoming.presence || today).min_by { |slot| (slot.scheduled_at - at).abs }
  end

  # For the empty state: what is coming up, when today holds nothing to cook.
  def self.upcoming_planned(household, at: Time.current, within: 7.days, limit: 5)
    from = local_date(household, at)

    household.meal_plan_slots
             .with_recipe
             .includes(:recipe)
             .where(date: from..(from + within.in_days.to_i))
             .sort_by(&:scheduled_at)
             .select { |slot| slot.scheduled_at >= at }
             .first(limit)
  end

  # Which calendar day it is in the kitchen, which after 7pm in the Americas is
  # not the day a UTC server thinks it is.
  def self.local_date(household, at)
    at.in_time_zone(household.time_zone_object).to_date
  end
  private_class_method :local_date

  # A day either side, so a window that straddles midnight is still found.
  def self.around(household, at)
    on_date = local_date(household, at)

    household.meal_plan_slots
             .with_recipe
             .includes(:recipe)
             .where(date: (on_date - 1)..(on_date + 1))
             .to_a
  end
  private_class_method :around

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

  def leftover_capacity_remaining(excluding_slot: nil)
    capacity = recipe&.effective_leftover_capacity || 1
    used = if excluding_slot.present?
      leftover_slots.reject { |s| s.id == excluding_slot.id }.size
    else
      leftover_slots.size
    end
    [ capacity - used, 0 ].max
  end

  def leftover_exhausted?(excluding_slot: nil)
    leftover_capacity_remaining(excluding_slot: excluding_slot) <= 0
  end

  private

  def leftover_source_cannot_be_self
    if leftover_source_slot_id.present? && leftover_source_slot_id == id
      errors.add(:leftover_source_slot_id, "cannot be itself")
    end
  end

  def normalize_blank_attributes
    self.family_member_id = nil if family_member_id.blank?
    self.recipe_id = nil if recipe_id.blank?
    self.leftover_source_slot_id = nil if leftover_source_slot_id.blank? || !is_leftover?
  end

  def household_meal_time
    default = DEFAULT_MEAL_TIMES.fetch(meal_type, DEFAULT_MEAL_TIMES["dinner"])

    case meal_type
    when "breakfast" then household.breakfast_time.presence || default
    when "lunch" then household.lunch_time.presence || default
    else household.dinner_time.presence || default
    end
  end
  def fulfill_recipe_requests_if_passed
    return unless recipe.present? && date.present? && date <= Date.current

    recipe.recipe_requests.active.where("week_start_date <= ? OR created_at <= ?", date, date.end_of_day).find_each do |req|
      req.update_columns(fulfilled_at: date.to_time)
    end
  end
end
