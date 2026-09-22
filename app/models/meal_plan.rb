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
    target_rank = MealPlanSlot.meal_type_rank(target_meal_type)
    min_date = target_date - Recipe::MAX_LEFTOVER_SHELF_LIFE_DAYS.days

    # Query household-wide across all weekly plans for a rolling window up to the
    # maximum shelf life accepted by Recipe.
    slots_scope = if preloaded_sources.present?
      preloaded_sources.select { |s| s.date >= min_date && s.date <= target_date }
    else
      leftover_sources_between(min_date, target_date)
    end

    eligible_sources = slots_scope.filter_map do |slot|
      next false unless slot.recipe.present?

      next false unless MealPlanSlot.served_before?(slot, target_date: target_date, target_meal_type: target_meal_type)

      # Shelf life check: candidate must be within recipe's shelf life window
      shelf_life = slot.recipe.effective_leftover_shelf_life_days
      days_ago = (target_date - slot.date).to_i
      next false if days_ago > shelf_life

      # Capacity check: candidate must not be exhausted
      next false if slot.leftover_exhausted?(excluding_slot: current_slot)

      { slot: slot, shelf_life: shelf_life, days_ago: days_ago }
    end

    eligible_sources.sort_by do |source|
      rec = source[:slot].recipe
      is_yields = rec.yields_leftovers? ? 0 : 1
      rank_diff = target_rank - MealPlanSlot.meal_type_rank(source[:slot].meal_type)
      [ is_yields, source[:days_ago], -rank_diff ]
    end.uniq { |source| source[:slot].id }.map do |source|
      slot = source[:slot]
      rec = slot.recipe
      remaining_cap = slot.leftover_capacity_remaining(excluding_slot: current_slot)

      {
        slot: slot,
        recipe: rec,
        source_slot_id: slot.id,
        remaining_capacity: remaining_cap,
        days_remaining: [ source[:shelf_life] - source[:days_ago], 0 ].max,
        source_label: "#{slot.date.strftime('%a')} #{slot.meal_type.capitalize}"
      }
    end
  end

  private

  def leftover_sources_between(min_date, max_date)
    household.meal_plan_slots
             .includes(:recipe, :leftover_slots)
             .where(is_leftover: false)
             .where.not(recipe_id: nil)
             .where(date: min_date..max_date)
             .to_a
  end
end
