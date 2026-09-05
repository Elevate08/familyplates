class Recipe < ApplicationRecord
  # Re-derives the aisle mappings for this recipe's ingredients, once per
  # distinct name. Used after a bulk save that suspended the per-ingredient
  # callback.
  def resync_aisle_mappings!
    recipe_ingredients.map(&:name).compact_blank.uniq.each do |name|
      IngredientAisleMapping.sync_ingredient_usage!(name, household)
    end
  end

  belongs_to :household
  has_many :recipe_ingredients, dependent: :destroy
  has_many :recipe_requests, dependent: :destroy
  has_many :meal_plan_slots, dependent: :nullify
  has_one_attached :image

  accepts_nested_attributes_for :recipe_ingredients, allow_destroy: true, reject_if: proc { |attrs| attrs["name"].blank? && attrs["raw_text"].blank? }

  MEAL_TYPES = %w[breakfast lunch dinner].freeze

  POPULAR_TAGS = [
    "Quick",
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

  attribute :leftover_capacity, default: 1
  attribute :leftover_shelf_life_days, default: 3

  validates :title, presence: true, uniqueness: { scope: :household_id, case_sensitive: false, message: "already exists in your recipe box" }
  validates :number, presence: true, uniqueness: { scope: :household_id }
  validates :leftover_capacity, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 10 }, allow_nil: true
  validates :leftover_shelf_life_days, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 14 }, allow_nil: true
  before_validation :assign_number, on: :create, if: -> { household_id.present? && number.blank? }

  def effective_leftover_capacity
    leftover_capacity.presence || 1
  end

  def effective_leftover_shelf_life_days
    leftover_shelf_life_days.presence || 3
  end

  def assign_number
    self.number = (household.recipes.maximum(:number) || 0) + 1
  end

  def to_param
    number ? number.to_s : id.to_s
  end

  scope :alphabetical, -> { order(:title) }
  scope :quick, -> { where("(COALESCE(prep_time, 0) + COALESCE(cook_time, 0)) <= 30 OR LOWER(tags) LIKE '%quick%'") }
  scope :for_meal_type, ->(meal_type) { where("meal_types LIKE ? OR meal_types IS NULL OR meal_types = ''", "%#{meal_type}%") }
  scope :leftover_friendly, -> { where(yields_leftovers: true) }

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

  # One entry per step for Cook Mode, with any section heading and detected
  # timers attached. See CookingStepParser for the shapes instructions arrive in.
  def cooking_steps
    CookingStepParser.call(instructions)
  end

  def active_requests
    recipe_requests.active
  end

  def requested_by?(family_member, _week = nil)
    return false unless family_member
    recipe_requests.active.exists?(family_member: family_member)
  end

  def request_count_for_week(_week = nil)
    recipe_requests.active.count
  end

  def requesters_for_week(_week = nil)
    FamilyMember.joins(:recipe_requests)
                .where(recipe_requests: { recipe_id: id, fulfilled_at: nil })
  end

  def requester_names_for_week(_week = nil)
    requesters_for_week.pluck(:name)
  end
end
