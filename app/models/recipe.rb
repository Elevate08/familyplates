class Recipe < ApplicationRecord
  belongs_to :household
  has_many :recipe_ingredients, dependent: :destroy
  has_many :recipe_requests, dependent: :destroy
  has_many :meal_plan_slots, dependent: :nullify
  has_one_attached :image

  accepts_nested_attributes_for :recipe_ingredients, allow_destroy: true, reject_if: proc { |attrs| attrs["name"].blank? && attrs["raw_text"].blank? }

  MEAL_TYPES = %w[breakfast lunch dinner].freeze

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

  validates :title, presence: true, uniqueness: { scope: :household_id, case_sensitive: false, message: "already exists in your recipe box" }

  scope :alphabetical, -> { order(:title) }
  scope :quick, -> { where("(COALESCE(prep_time, 0) + COALESCE(cook_time, 0)) <= 30") }
  scope :for_meal_type, ->(meal_type) { where("meal_types LIKE ? OR meal_types IS NULL OR meal_types = ''", "%#{meal_type}%") }

  def display_image_url
    if image.attached?
      Rails.application.routes.url_helpers.rails_blob_path(image, only_path: true)
    elsif image_url.present?
      image_url
    else
      "https://images.unsplash.com/photo-1498837167922-ddd27525d352?auto=format&fit=crop&w=800&q=80"
    end
  end

  def meal_types_list
    if meal_types.blank?
      MEAL_TYPES
    else
      meal_types.to_s.split(",").map(&:strip).reject(&:blank?)
    end
  end

  def for_meal_type?(type)
    meal_types_list.include?(type.to_s)
  end

  def total_time
    read_attribute(:total_time).presence || ((prep_time || 0) + (cook_time || 0))
  end

  def additional_time
    tt = read_attribute(:total_time)
    base = (prep_time || 0) + (cook_time || 0)
    (tt && tt > base) ? (tt - base) : 0
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

  def requesters_for_week(week = Date.current.beginning_of_week)
    FamilyMember.joins(:recipe_requests)
                .where(recipe_requests: { recipe_id: id, week_start_date: week })
  end

  def requester_names_for_week(week = Date.current.beginning_of_week)
    requesters_for_week(week).pluck(:name)
  end
end
