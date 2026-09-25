module PlatformAuditEventsHelper
  def platform_audit_action_badge_classes(event_or_action)
    action = event_or_action.respond_to?(:action) ? event_or_action.action : event_or_action.to_s

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
