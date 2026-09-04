class User < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  has_secure_password validations: false

  has_many :identities, dependent: :destroy
  has_many :sessions, dependent: :destroy
  has_many :family_members, dependent: :nullify
  has_many :households, through: :family_members
  has_many :magic_codes, dependent: :destroy
  has_many :device_grants, dependent: :nullify
  has_many :passkeys, dependent: :destroy

  def webauthn_id
    id
  end

  normalizes :email, with: ->(email) { email.strip.downcase }

  validates :email, presence: true, uniqueness: { case_sensitive: false }

  def can_disconnect_identity?(identity)
    return false unless identities.exists?(id: identity.id)

    password_digest.present? || passkeys.exists? || identities.where.not(id: identity.id).exists?
  end

  def self.find_or_create_from_identity(provider:, uid:, email: nil, name: nil)
    provider = provider.to_s
    uid = uid.to_s

    identity = Identity.find_by(provider: provider, uid: uid)
    return identity.user if identity

    normalized_email = email.to_s.strip.downcase
    if normalized_email.present?
      user = User.find_by("LOWER(email) = ?", normalized_email)
      if user
        user.identities.create!(provider: provider, uid: uid)
        return user
      end
    end

    if normalized_email.blank?
      raise ActiveRecord::RecordInvalid.new(User.new), "Email cannot be blank when registering a new account."
    end

    User.transaction do
      user = User.create!(email: normalized_email)
      user.identities.create!(provider: provider, uid: uid)
      user
    end
  end
end
