class FamilyMember < ApplicationRecord
  belongs_to :household
  has_many :recipe_requests, dependent: :destroy
  has_many :meal_plan_slots, dependent: :nullify

  AVATAR_COLORS = [
    "#F97316", # Orange (Warm Carrot)
    "#3B82F6", # Blue (Ocean)
    "#10B981", # Emerald (Sage)
    "#F59E0B", # Amber (Golden)
    "#EF4444", # Red (Chili)
    "#8B5CF6", # Purple (Plum)
    "#EC4899", # Pink (Berry)
    "#14B8A6", # Teal (Mint)
    "#6366F1", # Indigo (Twilight)
    "#84CC16", # Lime (Olive)
    "#06B6D4", # Cyan (Sky)
    "#64748B"  # Slate (Graphite)
  ].freeze

  AVATAR_ICONS = %w[chef-hat utensils heart star smile flame sparkles award].freeze

  validates :name, presence: true
  validates :pin, presence: true, format: { with: /\A\d{4}\z/, message: "must be exactly 4 digits" }, if: :admin?
  before_validation :clear_pin_unless_admin

  def initial
    name.to_s.strip[0]&.upcase || "?"
  end

  def admin?
    role == "admin"
  end

  def requires_pin?
    admin?
  end

  # Constant-time, so a wrong PIN cannot be narrowed down by timing how long the
  # comparison takes. secure_compare returns false on a length mismatch rather
  # than raising, and PINs are a fixed four digits, so nothing is leaked by that.
  def verify_pin(input)
    stored = pin.to_s
    given = input.to_s.strip
    return false if stored.empty? || given.empty?

    ActiveSupport::SecurityUtils.secure_compare(stored, given)
  end

  private

  def clear_pin_unless_admin
    self.pin = nil unless admin?
  end
end
