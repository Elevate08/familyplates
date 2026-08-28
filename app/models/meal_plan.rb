class MealPlan < ApplicationRecord
  belongs_to :household
  has_many :meal_plan_slots, dependent: :destroy
  has_many :recipes, through: :meal_plan_slots

  validates :week_start_date, presence: true, uniqueness: { scope: :household_id }

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

  def available_leftovers_for(target_date, target_meal_type)
    target_rank = MEAL_TYPE_ORDER[target_meal_type.to_s] || 2
    min_date = target_date - 3.days

    # Query household-wide across all weekly plans for a rolling 3-day leftover window
    slots_scope = household.meal_plan_slots
                           .includes(:recipe)
                           .where(is_leftover: false)
                           .where.not(recipe_id: nil)
                           .where("date >= ? AND date <= ?", min_date, target_date)

    prior_slots = slots_scope.select do |slot|
      if slot.date < target_date
        true
      elsif slot.date == target_date
        slot_rank = MEAL_TYPE_ORDER[slot.meal_type.to_s] || 1
        slot_rank < target_rank
      else
        false
      end
    end

    prior_slots.sort_by do |slot|
      rec = slot.recipe
      is_yields = rec&.yields_leftovers? ? 0 : 1
      days_ago = (target_date - slot.date).to_i
      rank_diff = target_rank - (MEAL_TYPE_ORDER[slot.meal_type.to_s] || 1)
      [is_yields, days_ago, -rank_diff]
    end.map do |slot|
      {
        slot: slot,
        recipe: slot.recipe,
        source_label: "#{slot.date.strftime('%a')} #{slot.meal_type.capitalize}"
      }
    end.uniq { |item| item[:recipe].id }
  end
end
