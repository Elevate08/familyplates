class Identity < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :user

  validates :provider, :uid, presence: true
  validates :uid, uniqueness: { scope: :provider }

  scope :oauth, -> { where(provider: %w[google apple oidc]) }
  scope :external, -> { where(provider: %w[google apple oidc forward_auth]) }

  def display_provider
    case provider
    when "google" then "Google"
    when "apple" then "Apple"
    when "oidc" then FamilyPlates.config.oidc_display_name
    when "forward_auth" then "Reverse Proxy SSO"
    when "passkey" then "Passkey"
    else provider.titleize
    end
  end
end
