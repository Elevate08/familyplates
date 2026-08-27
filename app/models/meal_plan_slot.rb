class MealPlanSlot < ApplicationRecord
  belongs_to :meal_plan
  belongs_to :recipe, optional: true
  belongs_to :family_member, optional: true

  MEAL_TYPES = %w[breakfast lunch dinner].freeze

  validates :date, presence: true
  validates :meal_type, inclusion: { in: MEAL_TYPES }
  validates :meal_type, uniqueness: { scope: [:meal_plan_id, :date], message: "slot already exists for this date and meal type" }

  def display_title
    recipe&.title.presence || custom_title.presence || "No Meal Planned"
  end

  def cook_name
    family_member&.name
  end
end
