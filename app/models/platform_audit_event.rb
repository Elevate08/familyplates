class PlatformAuditEvent < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :platform_admin, class_name: "PlatformAdminAccount", optional: true

  validates :action, presence: true

  scope :without_views, -> { where.not("action LIKE ? OR action LIKE ?", "%.viewed", "%.indexed") }

  scope :for_category, ->(category) {
    case category.to_s
    when "changes" then without_views
    when "auth" then where("action LIKE ?", "platform_admin.%")
    when "households" then where("action LIKE ?", "household%")
    when "support" then where("action LIKE ?", "support_thread.%")
    when "promotions" then where("action LIKE ?", "promotion_program.%")
    else all
    end
  }

  scope :search, ->(query) {
    return all if query.blank?

    pattern = "%#{query.strip}%"
    where(
      "action LIKE :p OR target_type LIKE :p OR target_id LIKE :p OR ip_address LIKE :p OR metadata LIKE :p",
      p: pattern
    )
  }

  def self.record!(action:, actor: nil, target: nil, metadata: {}, request: nil)
    create!(
      action: action,
      platform_admin: actor,
      target_type: target&.class&.base_class&.name,
      target_id: target&.id&.to_s,
      metadata: metadata.stringify_keys,
      ip_address: request&.remote_ip,
      user_agent: request&.user_agent
    )
  end

  def view_event?
    action.end_with?(".viewed", ".indexed")
  end

  def action_badge_classes
    case action
    when "platform_admin.sign_in_failed", "household.suspended", "household.permanently_deleted"
      "bg-rose-100 dark:bg-rose-950/80 text-rose-800 dark:text-rose-300 border-rose-200 dark:border-rose-900"
    when "platform_admin.signed_in", "household.restored", "support_thread.resolved"
      "bg-emerald-100 dark:bg-emerald-950/80 text-emerald-800 dark:text-emerald-300 border-emerald-200 dark:border-emerald-900"
    when "support_thread.replied", "support_thread.reopened", "support_thread.status_changed"
      "bg-sky-100 dark:bg-sky-950/80 text-sky-800 dark:text-sky-300 border-sky-200 dark:border-sky-900"
    when "promotion_program.created", "promotion_program.updated"
      "bg-indigo-100 dark:bg-indigo-950/80 text-indigo-800 dark:text-indigo-300 border-indigo-200 dark:border-indigo-900"
    else
      "bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300 border-slate-200 dark:border-slate-700"
    end
  end
end
