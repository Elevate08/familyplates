module SupportThreadsHelper
  def support_thread_status_badge(thread_or_status)
    status_key = thread_or_status.is_a?(SupportThread) ? thread_or_status.display_status : thread_or_status.to_s
    status_key = "waiting_on_support" if status_key == "open"

    case status_key
    when "waiting_on_support"
      content_tag(:span, class: "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-bold bg-amber-50 text-amber-800 border border-amber-200 dark:bg-amber-950/60 dark:text-amber-300 dark:border-amber-800/80 shadow-2xs") do
        concat content_tag(:span, "", class: "w-1.5 h-1.5 rounded-full bg-amber-500 animate-pulse")
        concat "Waiting on support"
      end
    when "waiting_on_customer"
      content_tag(:span, class: "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-bold bg-sky-50 text-sky-800 border border-sky-200 dark:bg-sky-950/60 dark:text-sky-300 dark:border-sky-800/80 shadow-2xs") do
        concat content_tag(:span, "", class: "w-1.5 h-1.5 rounded-full bg-sky-500")
        concat "Waiting on customer"
      end
    when "resolved"
      content_tag(:span, class: "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-bold bg-emerald-50 text-emerald-800 border border-emerald-200 dark:bg-emerald-950/60 dark:text-emerald-300 dark:border-emerald-800/80 shadow-2xs") do
        concat content_tag(:span, "", class: "w-1.5 h-1.5 rounded-full bg-emerald-500")
        concat "Resolved"
      end
    else
      content_tag(:span, class: "inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-bold bg-slate-100 text-slate-700 border border-slate-200 dark:bg-slate-800 dark:text-slate-300 dark:border-slate-700 shadow-2xs") do
        concat status_key.humanize
      end
    end
  end
end
