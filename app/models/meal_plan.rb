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
      "#{week_start_date.strftime('%B %-d')} – #{end_date.strftime('%B %-d, %Y')}"
    end
  end
end
