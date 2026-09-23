class MealPlan < ApplicationRecord
  belongs_to :household
  has_many :meal_plan_slots, dependent: :destroy
  has_many :recipes, through: :meal_plan_slots

  validates :week_start_date, presence: true, uniqueness: { scope: :household_id }
  validates :number, presence: true, uniqueness: { scope: :household_id }
  before_validation :assign_number, on: :create, if: -> { household_id.present? && number.blank? }

  def assign_number
    self.number = (household.meal_plans.maximum(:number) || 0) + 1
  end

  def to_param
    number ? number.to_s : id.to_s
  end

  def days
    (0..6).map { |i| week_start_date + i.days }
  end

  def slot_for(date, meal_type)
    if meal_plan_slots.loaded?
      meal_plan_slots.find { |s| s.date == date && s.meal_type == meal_type }
    else
      meal_plan_slots.find_by(date: date, meal_type: meal_type)
    end
  end

  def preloaded_leftover_sources
    leftover_sources_between(
      week_start_date - Recipe::MAX_LEFTOVER_SHELF_LIFE_DAYS.days,
      week_start_date + 6.days
    )
  end

  def week_label
    end_date = week_start_date + 6.days
    if week_start_date.month == end_date.month
      "#{week_start_date.strftime('%B %-d')} – #{end_date.strftime('%-d, %Y')}"
    else
      "#{week_start_date.strftime('%b %-d')} – #{end_date.strftime('%b %-d, %Y')}"
    end
  end

  MEAL_TYPE_ORDER = MealPlanSlot::MEAL_TYPE_ORDER

  def available_leftovers_for(target_date, target_meal_type, current_slot: nil, preloaded_sources: nil)
    leftover_candidates(target_date, target_meal_type, current_slot, preloaded_sources)
      .sort_by { |source| leftover_sort_key(source, target_meal_type) }
      .uniq { |source| source[:slot].id }
      .map { |source| leftover_option(source, current_slot) }
  end

  private

  def leftover_candidates(target_date, target_meal_type, current_slot, preloaded_sources)
    min_date = target_date - Recipe::MAX_LEFTOVER_SHELF_LIFE_DAYS.days
    slots = if preloaded_sources.present?
      # Already loaded for this week. Still household-wide: the caller preloads
      # a rolling window up to Recipe's maximum shelf life.
      preloaded_sources.select { |slot| slot.date >= min_date && slot.date <= target_date }
    else
      leftover_sources_between(min_date, target_date)
    end

    slots.filter_map { |slot| leftover_candidate(slot, target_date, target_meal_type, current_slot) }
  end

  def leftover_candidate(slot, target_date, target_meal_type, current_slot)
    return unless slot.recipe.present?
    return unless MealPlanSlot.served_before?(slot, target_date: target_date, target_meal_type: target_meal_type)

    shelf_life = slot.recipe.effective_leftover_shelf_life_days
    days_ago = (target_date - slot.date).to_i
    return if days_ago > shelf_life
    return if slot.leftover_exhausted?(excluding_slot: current_slot)

    { slot: slot, shelf_life: shelf_life, days_ago: days_ago }
  end

  def leftover_sort_key(source, target_meal_type)
    yields_rank = source[:slot].recipe.yields_leftovers? ? 0 : 1
    rank_diff = MealPlanSlot.meal_type_rank(target_meal_type) - MealPlanSlot.meal_type_rank(source[:slot].meal_type)
    [ yields_rank, source[:days_ago], -rank_diff ]
  end

  def leftover_option(source, current_slot)
    slot = source[:slot]

    {
      slot: slot,
      recipe: slot.recipe,
      source_slot_id: slot.id,
      remaining_capacity: slot.leftover_capacity_remaining(excluding_slot: current_slot),
      days_remaining: [ source[:shelf_life] - source[:days_ago], 0 ].max,
      source_label: "#{slot.date.strftime('%a')} #{slot.meal_type.capitalize}"
    }
  end

  def leftover_sources_between(min_date, max_date)
    household.meal_plan_slots
             .includes(:recipe, :leftover_slots)
             .where(is_leftover: false)
             .where.not(recipe_id: nil)
             .where(date: min_date..max_date)
             .to_a
  end
end
