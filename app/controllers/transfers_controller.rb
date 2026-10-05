class TransfersController < ApplicationController
  allow_unauthenticated_access only: %i[show claim]
  # Claiming asks for the claimant's own Terms acceptance in its form.
  allow_without_current_terms only: %i[show claim]
  before_action :set_member

  def show
  end

  def claim
    unless current_user
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path, alert: "Please sign in to claim this profile." and return
    end

    if current_user.family_members.where(household: @member.household).where.not(id: @member.id).exists?
      redirect_to root_path, alert: "You already have an active profile in this household." and return
    end

    # Hosted: the claimant accepts the current Terms themselves. Claiming a
    # profile, even the owner's, never carries the owner's acceptance or
    # payment authority with it.
    if (problem = terms_assent_problem)
      flash.now[:alert] = problem
      render :show, status: terms_assent_problem_status(problem) and return
    end

    transferred = FamilyMember.transaction do
      @member.transfer_to!(current_user).tap do |ok|
        record_terms_assent!(context: "claim", household: @member.household) if ok
      end
    end
    unless transferred
      redirect_to select_profile_path, alert: "This transfer link is invalid or has expired." and return
    end
    start_new_session_for(@member)
    redirect_to root_path, notice: "Profile #{@member.name} successfully transferred to your account!"
  end

  private

  def set_member
    @member = FamilyMember.find_by_transfer_id(params[:token])
    unless @member
      redirect_to select_profile_path, alert: "This transfer link is invalid or has expired."
    end
  end
end
