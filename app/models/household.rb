class Household < ApplicationRecord
  has_many :family_members, dependent: :destroy
  has_many :pantry_items, dependent: :destroy
  has_many :recipes, dependent: :destroy
  has_many :meal_plans, dependent: :destroy
  has_many :meal_plan_slots, through: :meal_plans

  validates :name, presence: true

  def current_meal_plan(week_date = Date.current.beginning_of_week)
    meal_plans.find_or_create_by!(week_start_date: week_date)
  end
end
