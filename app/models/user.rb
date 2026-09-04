class User < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  has_secure_password validations: false

  has_many :identities, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :family_members, dependent: :nullify
  has_many :households, through: :family_members
  has_many :magic_codes, dependent: :destroy
  has_many :device_grants, dependent: :nullify

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: { case_sensitive: false }
end
