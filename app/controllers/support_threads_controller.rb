class SupportThreadsController < ApplicationController
  before_action :set_support_thread, only: :show

  def index
    @support_threads = current_household.support_threads.order(last_message_at: :desc, created_at: :desc)
  end

  def show
    @support_message = @support_thread.messages.build
  end

  def create
    unless current_user
      redirect_to root_path, alert: "Please sign in with a customer account before contacting support."
      return
    end

    @support_thread = current_household.support_threads.new(thread_params.merge(created_by_user: current_user))
    if @support_thread.save
      @support_thread.messages.create!(user: current_user, body: params.dig(:support_thread, :body))
      redirect_to @support_thread, notice: "Your support request has been sent."
    else
      @support_threads = current_household.support_threads.order(last_message_at: :desc, created_at: :desc)
      render :index, status: :unprocessable_entity
    end
  end

  private

  def set_support_thread
    @support_thread = current_household.support_threads.find(params[:id])
  end

  def thread_params
    params.require(:support_thread).permit(:subject)
  end
end
