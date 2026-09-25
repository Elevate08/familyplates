class AccountDeletionRequest < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :household
  belongs_to :requested_by_user, class_name: "User", optional: true
  belongs_to :resolved_by_platform_admin, class_name: "PlatformAdminAccount", optional: true

  enum :status, { pending: "pending", canceled: "canceled", completed: "completed" }, validate: true

  validates :requested_at, presence: true
  validate :only_one_pending_request

  private

  def only_one_pending_request
    return unless pending? && household_id.present?
    return unless household.account_deletion_requests.pending.where.not(id: id).exists?

    errors.add(:base, "A deletion request is already pending")
  end
end
