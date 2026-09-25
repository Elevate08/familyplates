module PlatformAdmin
  class SupportThreadsController < BaseController
    before_action :set_support_thread, only: %i[show reply resolve reopen change_status]

    def index
      @filter = params[:status].presence || "active"
      base_scope = SupportThread.includes(:household, :messages).order(last_message_at: :desc, created_at: :desc)

      @waiting_on_support_count = SupportThread.waiting_on_support_only.count
      @waiting_on_customer_count = SupportThread.waiting_on_customer_only.count
      @resolved_count = SupportThread.resolved_only.count
      @active_count = @waiting_on_support_count + @waiting_on_customer_count

      case @filter
      when "waiting_on_support"
        @active_threads = base_scope.waiting_on_support_only
        @resolved_threads = []
      when "waiting_on_customer"
        @active_threads = base_scope.waiting_on_customer_only
        @resolved_threads = []
      when "resolved"
        @active_threads = []
        @resolved_threads = base_scope.resolved_only
      when "all"
        @active_threads = base_scope.active
        @resolved_threads = base_scope.resolved_only
      else # "active"
        @active_threads = base_scope.active
        @resolved_threads = base_scope.resolved_only.limit(25)
      end
    end

    def show
      @household = @support_thread.household
      record_platform_audit!("support_thread.viewed", target: @support_thread)
      @support_message = @support_thread.messages.build
    end

    def reply
      @support_thread.messages.create!(platform_admin: current_platform_admin, body: message_params[:body])
      record_platform_audit!("support_thread.replied", target: @support_thread)
      redirect_to_thread notice: "Reply sent."
    rescue ActiveRecord::RecordInvalid
      redirect_to_thread alert: "We could not send that reply."
    end

    def resolve
      @support_thread.resolve!
      record_platform_audit!("support_thread.resolved", target: @support_thread)
      redirect_to_thread notice: "Support thread resolved."
    end

    def reopen
      @support_thread.reopen!(by: current_platform_admin)
      record_platform_audit!("support_thread.reopened", target: @support_thread)
      redirect_to_thread notice: "Support thread reopened."
    end

    def change_status
      target_status = params[:status].to_s
      if SupportThread::OPERATOR_SETTABLE_STATUSES.include?(target_status)
        @support_thread.change_status!(target_status)
        record_platform_audit!("support_thread.status_changed", target: @support_thread, metadata: { status: target_status })
        redirect_to_thread notice: "Status updated to #{target_status.humanize}."
      else
        redirect_to_thread alert: "Invalid status."
      end
    end

    private

    def redirect_to_thread(**flash)
      redirect_to platform_admin_support_thread_path(@support_thread), **flash
    end

    def set_support_thread
      @support_thread = SupportThread.includes(:household, messages: [ :user, :platform_admin ]).find(params[:id])
    end

    def message_params
      params.require(:support_message).permit(:body)
    end
  end
end
