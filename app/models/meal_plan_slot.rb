class MealPlanSlot < ApplicationRecord
  belongs_to :meal_plan
  belongs_to :recipe, optional: true
  belongs_to :family_member, optional: true
  belongs_to :leftover_source_slot, class_name: "MealPlanSlot", optional: true, inverse_of: :leftover_slots
  has_many :leftover_slots, class_name: "MealPlanSlot", foreign_key: :leftover_source_slot_id, dependent: :destroy, inverse_of: :leftover_source_slot

  delegate :household, to: :meal_plan

  MEAL_TYPES = %w[breakfast lunch dinner].freeze
  MEAL_TYPE_ORDER = MEAL_TYPES.each_with_index.to_h { |meal_type, index| [ meal_type, index + 1 ] }.freeze

  # Fallbacks for a household row that predates the meal-time columns; the
  # columns themselves default to these same values.
  DEFAULT_MEAL_TIMES = { "breakfast" => "08:00", "lunch" => "12:30", "dinner" => "18:00" }.freeze

  # "Cooking now" is a window: 2 hours before serving, 90 minutes after.
  COOKING_LEAD = 2.hours
  COOKING_GRACE = 90.minutes

  validates :date, presence: true
  validates :meal_type, inclusion: { in: MEAL_TYPES }
  validates :meal_type, uniqueness: { scope: [ :meal_plan_id, :date ], message: "slot already exists for this date and meal type" }
  validate :leftover_source_cannot_be_self
  validate :recipe_belongs_to_household
  validate :cook_belongs_to_household
  validate :validate_leftover_source_and_capacity, if: -> { is_leftover? && recipe_id.present? }
  before_validation :normalize_blank_attributes
  before_validation :drop_ineligible_leftover_source
  before_validation :auto_assign_leftover_source

  scope :leftovers, -> { where(is_leftover: true) }
  scope :fresh_meals, -> { where(is_leftover: false) }
  scope :with_recipe, -> { where.not(recipe_id: nil) }

  after_save :fulfill_recipe_requests_if_passed
  after_save :reset_leftover_source_association
  after_destroy :reset_leftover_source_association
  after_update :clear_invalidated_leftovers, if: -> { saved_change_to_recipe_id? || saved_change_to_is_leftover? || saved_change_to_date? || saved_change_to_meal_type? }

  # Slot time, else the household meal time. Built in the household zone:
  # "dinner at 6pm" is 6 in that kitchen, not 6 on a UTC server. The calendar feed uses the same fields.
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

  def self.meal_type_rank(meal_type)
    MEAL_TYPE_ORDER.fetch(meal_type.to_s, 1)
  end

  def self.served_before?(source_slot, target_date:, target_meal_type:)
    return true if source_slot.date < target_date
    return false if source_slot.date > target_date

    meal_type_rank(source_slot.meal_type) < meal_type_rank(target_meal_type)
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

  # Destroying the occupant and updating must be one transaction. Doing the
  # destroy first left the destination gone when the update failed.
  # True on success, false with errors — same contract as #update.
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

  def planned?
    recipe.present? || custom_title.present?
  end

  def cook_name
    family_member&.name
  end

  def leftover_capacity_remaining(excluding_slot: nil)
    capacity = recipe&.effective_leftover_capacity || Recipe::DEFAULT_LEFTOVER_CAPACITY
    used = if leftover_slots.loaded?
      slots = leftover_slots.to_a
      if excluding_slot.present?
        slots.reject { |s| s.equal?(excluding_slot) || (s.id.present? && s.id == excluding_slot.id) }.size
      else
        slots.size
      end
    else
      query = leftover_slots
      query = query.where.not(id: excluding_slot.id) if excluding_slot.present? && excluding_slot.id.present?
      query.count
    end
    [ capacity - used, 0 ].max
  end

  def leftover_exhausted?(excluding_slot: nil)
    leftover_capacity_remaining(excluding_slot: excluding_slot) <= 0
  end

  private

  def validate_leftover_source_and_capacity
    if leftover_source_slot.nil?
      has_prior_cooked = household.meal_plan_slots.where(is_leftover: false, recipe_id: recipe_id).exists?
      if has_prior_cooked
        errors.add(:base, "All leftover servings for #{recipe&.title} have already been scheduled.")
      else
        errors.add(:base, "#{recipe&.title} has not been cooked yet, so leftovers cannot be scheduled.")
      end
    elsif leftover_source_slot.leftover_exhausted?(excluding_slot: self)
      errors.add(:base, "All leftover servings for #{recipe&.title} have already been scheduled.")
    end
  end

  # A moved leftover carries its old source id. Drop a source from another household,
  # another recipe, or outside the shelf life so auto-assign or validation can replace it.
  def drop_ineligible_leftover_source
    return unless is_leftover? && leftover_source_slot_id.present?
    return if leftover_source_slot_id == id # reported by leftover_source_cannot_be_self
    return if eligible_leftover_source?(leftover_source_slot)

    self.leftover_source_slot = nil
  end

  def eligible_leftover_source?(source)
    return false if source.nil? || meal_plan.nil? || date.nil?
    return false if source.is_leftover? || source.recipe_id != recipe_id
    return false unless source.meal_plan&.household_id == meal_plan.household_id
    return false unless self.class.served_before?(source, target_date: date, target_meal_type: meal_type)

    shelf_life = source.recipe&.effective_leftover_shelf_life_days || Recipe::DEFAULT_LEFTOVER_SHELF_LIFE_DAYS
    (date - source.date).to_i <= shelf_life
  end

  def auto_assign_leftover_source
    return unless is_leftover? && recipe_id.present? && leftover_source_slot_id.blank? && leftover_source_slot.blank?
    return unless household.present?

    target_date = date || Date.current
    candidates = household.meal_plan_slots
                          .where(is_leftover: false, recipe_id: recipe_id)
                          .where("date <= ?", target_date)
                          .order(date: :desc, id: :desc)
                          .to_a

    source = candidates.find { |candidate| usable_leftover_source?(candidate, target_date) }

    self.leftover_source_slot_id = source&.id if source.present?
  end

  def usable_leftover_source?(candidate, target_date)
    return false if candidate.id == id
    return false unless self.class.served_before?(candidate, target_date: target_date, target_meal_type: meal_type)

    shelf_life = candidate.recipe&.effective_leftover_shelf_life_days || Recipe::DEFAULT_LEFTOVER_SHELF_LIFE_DAYS
    return false if (target_date - candidate.date).to_i > shelf_life

    !candidate.leftover_exhausted?(excluding_slot: self)
  end

  # recipe_id and family_member_id are client-supplied. Recipe ids are
  # sequential, so without this a household can read a neighbour's recipe by
  # counting. A missing row fails closed the same way a foreign household does.
  def recipe_belongs_to_household
    return if recipe_id.blank? || meal_plan.nil?
    return if recipe&.household_id == meal_plan.household_id

    errors.add(:recipe, "must belong to this household")
  end

  def cook_belongs_to_household
    return if family_member_id.blank? || meal_plan.nil?
    return if family_member&.household_id == meal_plan.household_id

    errors.add(:family_member, "must belong to this household")
  end

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

    recipe.recipe_requests.active.where("week_start_date <= ? OR created_at <= ?", date, date.end_of_day).update_all(fulfilled_at: date.to_time)
  end

  def reset_leftover_source_association
    leftover_source_slot&.association(:leftover_slots)&.reset
  end

  def clear_invalidated_leftovers
    return if leftover_slots.empty?

    if saved_change_to_recipe_id? || (saved_change_to_is_leftover? && is_leftover?)
      leftover_slots.destroy_all
    elsif saved_change_to_date? || saved_change_to_meal_type?
      shelf_life = recipe&.effective_leftover_shelf_life_days || Recipe::DEFAULT_LEFTOVER_SHELF_LIFE_DAYS

      leftover_slots.find_each do |child|
        days_diff = (child.date - date).to_i
        if !self.class.served_before?(self, target_date: child.date, target_meal_type: child.meal_type) || days_diff > shelf_life
          child.destroy
        end
      end
    end
  end
end
