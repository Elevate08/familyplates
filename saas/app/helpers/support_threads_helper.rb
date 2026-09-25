module SupportThreadsHelper
  STATUS_BADGES = {
    "waiting_on_support" => {
      label: "Waiting on support",
      colors: "bg-amber-50 text-amber-800 border border-amber-200 dark:bg-amber-950/60 dark:text-amber-300 dark:border-amber-800/80",
      dot: "bg-amber-500 animate-pulse"
    },
    "waiting_on_customer" => {
      label: "Waiting on customer",
      colors: "bg-sky-50 text-sky-800 border border-sky-200 dark:bg-sky-950/60 dark:text-sky-300 dark:border-sky-800/80",
      dot: "bg-sky-500"
    },
    "resolved" => {
      label: "Resolved",
      colors: "bg-emerald-50 text-emerald-800 border border-emerald-200 dark:bg-emerald-950/60 dark:text-emerald-300 dark:border-emerald-800/80",
      dot: "bg-emerald-500"
    }
  }.freeze

  FALLBACK_BADGE_COLORS = "bg-slate-100 text-slate-700 border border-slate-200 dark:bg-slate-800 dark:text-slate-300 dark:border-slate-700"

  def support_thread_status_badge(thread_or_status)
    raw_status = thread_or_status.is_a?(SupportThread) ? thread_or_status.status : thread_or_status
    status_key = SupportThread.display_status_for(raw_status)
    badge = STATUS_BADGES[status_key]
    colors = badge ? badge[:colors] : FALLBACK_BADGE_COLORS

    content_tag(:span, class: "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-bold #{colors} shadow-2xs") do
      if badge
        concat content_tag(:span, "", class: "w-1.5 h-1.5 rounded-full #{badge[:dot]}")
        concat badge[:label]
      else
        concat status_key.humanize
      end
    end
  end
end
