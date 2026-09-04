module PlatformAdmin
  class SupportThreadsController < BaseController
    def index
      @status = params[:status].presence_in(SupportThread.statuses.keys)
      @support_threads = SupportThread.includes(:household, :messages)
        .then { |scope| @status ? scope.where(status: @status) : scope }
        .order(last_message_at: :desc, created_at: :desc)
    end

    def show
      @support_thread = SupportThread.includes(:household, messages: [ :user, :platform_admin ]).find(params[:id])
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

    private

    def message_params
      params.require(:support_message).permit(:body)
    end
  end
end
