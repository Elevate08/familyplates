class RecipeRequest < ApplicationRecord
  belongs_to :recipe
  belongs_to :family_member

  validates :week_start_date, presence: true
  validates :recipe_id, uniqueness: { scope: [:family_member_id, :week_start_date], message: "has already been requested by this family member for this week" }
end
