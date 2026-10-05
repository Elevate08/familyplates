# frozen_string_literal: true

# Evidence that a person agreed to a version of the hosted Terms of Service:
# who, which version, when, and how (sign-up, joining a household, claiming a
# profile, or accepting a new version). Append-only, and without foreign keys:
# it outlives the user and household it names. Nothing else is kept - no
# email address, IP address or household content.
class TermsAcceptance < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  validates :user_id, :terms_version, :accepted_at, presence: true
  validates :context, inclusion: { in: TermsAssent::CONTEXTS }

  def readonly?
    persisted?
  end
end
