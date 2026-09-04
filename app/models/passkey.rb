# frozen_string_literal: true

require "securerandom"

class Passkey < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :public_key, presence: true
  validates :sign_count, presence: true, numericality: { greater_than_or_equal_to: 0 }

  after_create :sync_identity
  after_destroy :cleanup_identity

  def label
    nickname.presence || "Passkey (#{created_at.strftime('%b %d, %Y')})"
  end

  def update_sign_count!(new_count)
    update!(sign_count: new_count, last_used_at: Time.current)
  end

  private

  def sync_identity
    user.identities.find_or_create_by!(provider: "passkey", uid: external_id)
  end

  def cleanup_identity
    user.identities.find_by(provider: "passkey", uid: external_id)&.destroy
  end
end
