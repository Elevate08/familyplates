class SupportMessagesController < ApplicationController
  allow_suspended_access

  def create
    thread = current_household.support_threads.find(params[:support_thread_id])
    created = current_user && thread.messages.create(user: current_user, body: message_params[:body]).persisted?

    if created
      redirect_to thread, notice: "Your reply has been sent."
    else
      redirect_to thread, alert: "We could not send that reply. Please try again."
    end
  end

  private

  def message_params
    params.require(:support_message).permit(:body)
  end
end
