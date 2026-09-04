class PromotionProgram < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  normalizes :code, with: ->(value) { value.to_s.strip.upcase }

  validates :name, :code, presence: true
  validates :code, uniqueness: true
  validates :discount_percent, numericality: { only_integer: true, in: 1..100 }, allow_nil: true
  validates :max_redemptions, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  def currently_active?
    return false unless active?
    return false if starts_at.present? && starts_at.future?
    return false if ends_at.present? && ends_at.past?
    return false if max_redemptions.present? && redeemed_count >= max_redemptions

    true
  end
end
