class RecipeIngredient < ApplicationRecord
  belongs_to :recipe

  AISLE_CATEGORIES = [
    "Produce",
    "Meat & Seafood",
    "Dairy & Refrigerated",
    "Bakery",
    "Pantry & Grains",
    "Spices & Baking",
    "Frozen",
    "Other"
  ].freeze

  validates :name, presence: true
  validates :aisle_category, inclusion: { in: AISLE_CATEGORIES }

  before_validation :normalize_fields

  private

  def normalize_fields
    self.aisle_category = "Other" if aisle_category.blank?
    if name.blank? && raw_text.present?
      self.name = raw_text.strip
    end
  end
end
