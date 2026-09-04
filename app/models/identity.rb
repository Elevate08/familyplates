class Identity < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :user

  validates :provider, :uid, presence: true
  validates :uid, uniqueness: { scope: :provider }
end
