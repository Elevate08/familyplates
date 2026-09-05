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
    meal_plan_slots.find_by(date: date, meal_type: meal_type)
  end

  def week_label
    end_date = week_start_date + 6.days
    if week_start_date.month == end_date.month
      "#{week_start_date.strftime('%B %-d')} – #{end_date.strftime('%-d, %Y')}"
    else
      "#{week_start_date.strftime('%b %-d')} – #{end_date.strftime('%b %-d, %Y')}"
    end
  end

  MEAL_TYPE_ORDER = { "breakfast" => 1, "lunch" => 2, "dinner" => 3 }.freeze

  def available_leftovers_for(target_date, target_meal_type, current_slot: nil)
    target_rank = MEAL_TYPE_ORDER[target_meal_type.to_s] || 2
    min_date = target_date - 14.days

    # Query household-wide across all weekly plans for a rolling window up to max shelf life (14 days)
    slots_scope = household.meal_plan_slots
                           .includes(:recipe, :leftover_slots)
                           .where(is_leftover: false)
                           .where.not(recipe_id: nil)
                           .where("date >= ? AND date <= ?", min_date, target_date)

    prior_slots = slots_scope.select do |slot|
      next false unless slot.recipe.present?

      # Chronology check: must be strictly prior to target meal slot
      is_prior = if slot.date < target_date
        true
      elsif slot.date == target_date
        slot_rank = MEAL_TYPE_ORDER[slot.meal_type.to_s] || 1
        slot_rank < target_rank
      else
        false
      end
      next false unless is_prior

      # Shelf life check: candidate must be within recipe's shelf life window
      shelf_life = slot.recipe.effective_leftover_shelf_life_days
      days_ago = (target_date - slot.date).to_i
      next false if days_ago > shelf_life

      # Capacity check: candidate must not be exhausted
      next false if slot.leftover_exhausted?(excluding_slot: current_slot)

      true
    end

    prior_slots.sort_by do |slot|
      rec = slot.recipe
      is_yields = rec.yields_leftovers? ? 0 : 1
      days_ago = (target_date - slot.date).to_i
      rank_diff = target_rank - (MEAL_TYPE_ORDER[slot.meal_type.to_s] || 1)
      [ is_yields, days_ago, -rank_diff ]
    end.map do |slot|
      rec = slot.recipe
      days_ago = (target_date - slot.date).to_i
      shelf_life = rec.effective_leftover_shelf_life_days
      remaining_cap = slot.leftover_capacity_remaining(excluding_slot: current_slot)

      {
        slot: slot,
        recipe: rec,
        source_slot_id: slot.id,
        remaining_capacity: remaining_cap,
        days_remaining: [ shelf_life - days_ago, 0 ].max,
        source_label: "#{slot.date.strftime('%a')} #{slot.meal_type.capitalize}"
      }
    end.uniq { |item| item[:slot].id }
  end
end
