class ProfilesController < ApplicationController
  def select
    @family_members = current_household.family_members.order(:created_at)
  end

  def set
    member = current_household.family_members.find(params[:id])

    if member.requires_pin? && params[:pin].blank?
      flash[:alert] = "This profile is protected by a PIN."
      redirect_to select_profile_path(pin_member_id: member.id) and return
    end

    if member.requires_pin? && !member.verify_pin(params[:pin])
      flash[:alert] = "Incorrect 4-digit PIN for #{member.name}."
      redirect_to select_profile_path(pin_member_id: member.id) and return
    end

    cookies.signed[:active_family_member_id] = member.id
    redirect_to root_path, notice: "Welcome back, #{member.name}! 🍳"
  end
end
