class Session < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :user

  enum :kind, %w[browser kiosk].index_by(&:itself), default: :browser, validate: true

  validates :token, presence: true, uniqueness: true
  validates :last_active_at, presence: true
end
