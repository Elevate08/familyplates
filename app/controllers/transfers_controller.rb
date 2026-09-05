class TransfersController < ApplicationController
  allow_unauthenticated_access only: %i[show claim]
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

    @member.transfer_to!(current_user)
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
