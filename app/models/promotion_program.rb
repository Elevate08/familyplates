class PromotionProgram < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  normalizes :code, with: ->(value) { value.to_s.strip.upcase }

  validates :name, :code, presence: true
  validates :code, uniqueness: true
  validates :discount_percent, numericality: { only_integer: true, in: 1..100 }, allow_nil: true
  validates :max_redemptions, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  # Stripe counts redemptions, including codes customers type at Checkout, so
  # the count here is copied from it rather than kept separately.
  def self.refresh_redemptions!
    where(active: true).where.not(provider_promotion_code_id: [ nil, "" ]).find_each(&:refresh_redemptions!)
  end

  def refresh_redemptions!
    update!(redeemed_count: Stripe::PromotionCode.retrieve(provider_promotion_code_id).times_redeemed)
  rescue Stripe::StripeError => e
    Rails.logger.warn("[Promotions] Could not refresh #{code} (#{provider_promotion_code_id}): #{e.message}")
  end

  def currently_active?
    return false unless active?
    return false if starts_at.present? && starts_at.future?
    return false if ends_at.present? && ends_at.past?
    return false if max_redemptions.present? && redeemed_count >= max_redemptions

    true
  end
end
