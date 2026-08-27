class FamilyMember < ApplicationRecord
  belongs_to :household

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
  validates :pin, format: { with: /\A\d{4}\z/, message: "must be exactly 4 digits" }, allow_blank: true

  def initial
    name.to_s.strip[0]&.upcase || "?"
  end

  def admin?
    role == "admin"
  end

  def requires_pin?
    admin? && pin.present?
  end

  def verify_pin(input)
    pin.to_s == input.to_s.strip
  end
end
