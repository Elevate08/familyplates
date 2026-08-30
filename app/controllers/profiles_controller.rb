class ProfilesController < ApplicationController
  allow_unauthenticated_access only: %i[select set]

  def select
    if Household.none?
      redirect_to onboarding_path and return
    end
    household = current_household
    @family_members = household ? household.family_members.order(:id) : []
  end

  def set
    member = FamilyMember.find(params[:id])

    if member.requires_pin? && params[:pin].blank?
      flash[:alert] = "This profile is protected by a PIN."
      redirect_to select_profile_path(pin_member_id: member.id) and return
    end

    if member.requires_pin? && !member.verify_pin(params[:pin])
      flash[:alert] = "Incorrect 4-digit PIN for #{member.name}."
      redirect_to select_profile_path(pin_member_id: member.id) and return
    end

    start_new_session_for(member)
    target_url = after_authentication_url
    redirect_to target_url, notice: "Welcome to the kitchen, #{member.name}! 🍳"
  end
end
