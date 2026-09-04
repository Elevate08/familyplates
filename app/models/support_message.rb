class SupportMessage < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :thread, class_name: "SupportThread", foreign_key: :support_thread_id
  belongs_to :user, optional: true
  belongs_to :platform_admin, class_name: "PlatformAdminAccount", optional: true

  validates :body, presence: true, length: { maximum: 10_000 }
  validate :exactly_one_author

  after_create :update_thread_status

  def author
    platform_admin || user
  end

  def platform_admin?
    platform_admin.present?
  end

  private

  def exactly_one_author
    return if user.present? ^ platform_admin.present?

    errors.add(:base, "message must have exactly one author")
  end

  def update_thread_status
    thread.record_message!(self)
  end
end
