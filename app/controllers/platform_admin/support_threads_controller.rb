module PlatformAdmin
  class SupportThreadsController < BaseController
    def index
      @filter = params[:status].presence || "active"
      base_scope = SupportThread.includes(:household, :messages).order(last_message_at: :desc, created_at: :desc)

      @waiting_on_support_count = SupportThread.where(status: [ "waiting_on_support", "open" ]).count
      @waiting_on_customer_count = SupportThread.where(status: "waiting_on_customer").count
      @resolved_count = SupportThread.where(status: "resolved").count
      @active_count = @waiting_on_support_count + @waiting_on_customer_count

      case @filter
      when "waiting_on_support"
        @active_threads = base_scope.where(status: [ "waiting_on_support", "open" ])
        @resolved_threads = []
      when "waiting_on_customer"
        @active_threads = base_scope.where(status: "waiting_on_customer")
        @resolved_threads = []
      when "resolved"
        @active_threads = []
        @resolved_threads = base_scope.where(status: "resolved")
      when "all"
        @active_threads = base_scope.where(status: [ "waiting_on_support", "waiting_on_customer", "open" ])
        @resolved_threads = base_scope.where(status: "resolved")
      else # "active"
        @active_threads = base_scope.where(status: [ "waiting_on_support", "waiting_on_customer", "open" ])
        @resolved_threads = base_scope.where(status: "resolved").limit(25)
      end
    end

    def show
      @support_thread = SupportThread.includes(:household, messages: [ :user, :platform_admin ]).find(params[:id])
      @household = @support_thread.household
      record_platform_audit!("support_thread.viewed", target: @support_thread)
      @support_message = @support_thread.messages.build
    end

    def reply
      @support_thread = SupportThread.find(params[:id])
      @support_thread.messages.create!(platform_admin: current_platform_admin, body: message_params[:body])
      record_platform_audit!("support_thread.replied", target: @support_thread)
      redirect_to platform_admin_support_thread_path(@support_thread), notice: "Reply sent."
    rescue ActiveRecord::RecordInvalid
      redirect_to platform_admin_support_thread_path(@support_thread), alert: "We could not send that reply."
    end

    def resolve
      @support_thread = SupportThread.find(params[:id])
      @support_thread.resolve!
      record_platform_audit!("support_thread.resolved", target: @support_thread)
      redirect_to platform_admin_support_thread_path(@support_thread), notice: "Support thread resolved."
    end

    def reopen
      @support_thread = SupportThread.find(params[:id])
      @support_thread.reopen!(by: current_platform_admin)
      record_platform_audit!("support_thread.reopened", target: @support_thread)
      redirect_to platform_admin_support_thread_path(@support_thread), notice: "Support thread reopened."
    end

    def change_status
      @support_thread = SupportThread.find(params[:id])
      target_status = params[:status].to_s
      if %w[waiting_on_support waiting_on_customer resolved].include?(target_status)
        @support_thread.change_status!(target_status)
        record_platform_audit!("support_thread.status_changed", target: @support_thread, metadata: { status: target_status })
        redirect_to platform_admin_support_thread_path(@support_thread), notice: "Status updated to #{target_status.humanize}."
      else
        redirect_to platform_admin_support_thread_path(@support_thread), alert: "Invalid status."
      end
    end

    private

    def message_params
      params.require(:support_message).permit(:body)
    end
  end
end
