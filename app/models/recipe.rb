class Recipe < ApplicationRecord
  belongs_to :household
  has_many :recipe_ingredients, dependent: :destroy
  has_many :recipe_requests, dependent: :destroy
  has_many :meal_plan_slots, dependent: :nullify

  accepts_nested_attributes_for :recipe_ingredients, allow_destroy: true, reject_if: proc { |attrs| attrs["name"].blank? && attrs["raw_text"].blank? }

  POPULAR_TAGS = [
    "Quick (<30m)",
    "Kid Friendly",
    "Family Favorite",
    "One Pan",
    "Comfort Food",
    "Slow Cooker",
    "Healthy",
    "Vegetarian",
    "Pasta",
    "Mexican",
    "Italian",
    "Asian",
    "Seafood",
    "Weekend Grill"
  ].freeze

  validates :title, presence: true

  scope :alphabetical, -> { order(:title) }
  scope :quick, -> { where("(COALESCE(prep_time, 0) + COALESCE(cook_time, 0)) <= 30") }

  def display_image_url
    image_url.presence || "https://images.unsplash.com/photo-1498837167922-ddd27525d352?auto=format&fit=crop&w=800&q=80"
  end

  def total_time
    (prep_time || 0) + (cook_time || 0)
  end

  def tag_list
    tags.to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def requested_by?(family_member, week = Date.current.beginning_of_week)
    return false unless family_member
    recipe_requests.exists?(family_member: family_member, week_start_date: week)
  end

  def request_count_for_week(week = Date.current.beginning_of_week)
    recipe_requests.where(week_start_date: week).count
  end
end
