class RecipeRequest < ApplicationRecord
  belongs_to :recipe
  belongs_to :family_member

  scope :active, -> { where(fulfilled_at: nil) }
  scope :fulfilled, -> { where.not(fulfilled_at: nil) }

  validates :week_start_date, presence: true
  validate :only_one_active_request_per_family_member, on: :create

  # Fulfills active requests whose planned date on the calendar has arrived or passed
  def self.auto_fulfill_passed_slots!
    active.find_each do |req|
      min_date = [req.week_start_date, req.created_at&.to_date].compact.min || Date.current.beginning_of_week
      matching_slot = req.recipe.meal_plan_slots
                         .where("date <= ?", Date.current)
                         .where("date >= ?", min_date)
                         .order(date: :asc)
                         .first
      if matching_slot
        req.update_columns(fulfilled_at: matching_slot.date.to_time)
      end
    end
  end

  private

  def only_one_active_request_per_family_member
    if fulfilled_at.nil? && RecipeRequest.where(recipe_id: recipe_id, family_member_id: family_member_id, fulfilled_at: nil).exists?
      errors.add(:recipe_id, "has already been requested and is currently active")
    end
  end
end
