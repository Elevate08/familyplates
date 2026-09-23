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

  DEFAULT_LEFTOVER_CAPACITY = 1
  DEFAULT_LEFTOVER_SHELF_LIFE_DAYS = 3
  MAX_LEFTOVER_SHELF_LIFE_DAYS = 14
  # SVG and HTML served from this origin would run as script. The declared type
  # is what the browser is sent, so anything else is refused.
  ALLOWED_IMAGE_CONTENT_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  MAX_IMAGE_BYTES = 8.megabytes

  attribute :leftover_capacity, default: DEFAULT_LEFTOVER_CAPACITY
  attribute :leftover_shelf_life_days, default: DEFAULT_LEFTOVER_SHELF_LIFE_DAYS

  # Both columns are NOT NULL. A cleared form field arrives blank, which the
  # validations allow and the database then rejected with a 500 - so blank means
  # "back to the default" instead.
  before_validation :default_blank_leftover_settings

  validates :title, presence: true, uniqueness: { scope: :household_id, case_sensitive: false, message: "already exists in your recipe box" }
  validates :number, presence: true, uniqueness: { scope: :household_id }
  validates :leftover_capacity, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 10 }, allow_nil: true
  validates :leftover_shelf_life_days, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: MAX_LEFTOVER_SHELF_LIFE_DAYS }, allow_nil: true
  validate :acceptable_image, if: -> { image.attached? }
  before_validation :assign_number, on: :create, if: -> { household_id.present? && number.blank? }

  def effective_leftover_capacity
    leftover_capacity.presence || DEFAULT_LEFTOVER_CAPACITY
  end

  def effective_leftover_shelf_life_days
    leftover_shelf_life_days.presence || DEFAULT_LEFTOVER_SHELF_LIFE_DAYS
  end

  def assign_number
    self.number = (household.recipes.maximum(:number) || 0) + 1
  end

  def to_param
    number ? number.to_s : id.to_s
  end

  scope :alphabetical, -> { order(:title) }
  # "Quick" is the household's call, made by tagging the recipe - not a guess
  # from prep and cook time, which are often missing or leave out resting time.
  scope :quick, -> { where("LOWER(tags) LIKE ?", "%quick%") }
  scope :for_meal_type, ->(meal_type) {
    term = "%#{sanitize_sql_like(meal_type.to_s)}%"
    where("meal_types LIKE ? ESCAPE '\\' OR meal_types IS NULL OR meal_types = ''", term)
  }
  scope :leftover_friendly, -> { where(yields_leftovers: true) }

  def has_image?
    image.attached? || image_url.present?
  end

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
    # nil, not 0, when the recipe states no time at all - views show a dash for
    # that rather than claiming it takes no time.
    read_attribute(:total_time).presence || [ prep_time, cook_time ].compact.sum.nonzero?
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

  private

  def acceptable_image
    blob = image.blob
    unless ALLOWED_IMAGE_CONTENT_TYPES.include?(blob.content_type)
      errors.add(:image, "must be a JPEG, PNG, GIF, or WebP")
    end
    if blob.byte_size.to_i > MAX_IMAGE_BYTES
      errors.add(:image, "must be smaller than 8 MB")
    end
  end

  def default_blank_leftover_settings
    self.leftover_capacity = DEFAULT_LEFTOVER_CAPACITY if leftover_capacity_before_type_cast.blank?
    self.leftover_shelf_life_days = DEFAULT_LEFTOVER_SHELF_LIFE_DAYS if leftover_shelf_life_days_before_type_cast.blank?
  end
end
