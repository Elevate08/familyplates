class SupportThreadsController < ApplicationController
  allow_suspended_access

  before_action :set_support_thread, only: %i[show resolve]

  def index
    load_thread_lists
  end

  def show
    @support_message = @support_thread.messages.build
  end

  def resolve
    @support_thread.resolve!
    redirect_to @support_thread, notice: "Support request marked as resolved."
  end

  def create
    unless current_user
      redirect_to root_path, alert: "Please sign in with a customer account before contacting support."
      return
    end

    @support_thread = current_household.support_threads.new(thread_params.merge(created_by_user: current_user, status: "waiting_on_support"))
    # Built together so they save in one transaction: a blank message used to
    # raise after the thread was already saved, leaving an empty thread behind.
    @support_thread.messages.build(user: current_user, body: params.dig(:support_thread, :body))
    if @support_thread.save
      redirect_to @support_thread, notice: "Your support request has been sent."
    else
      load_thread_lists
      render :index, status: :unprocessable_entity
    end
  end

  private

  def load_thread_lists
    all_threads = current_household.support_threads.order(last_message_at: :desc, created_at: :desc)
    @active_threads = all_threads.active
    @resolved_threads = all_threads.resolved_only
    @support_threads = all_threads
  end

  def set_support_thread
    @support_thread = current_household.support_threads.find(params[:id])
  end

  def thread_params
    params.require(:support_thread).permit(:subject)
  end
end
