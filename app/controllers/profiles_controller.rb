class ProfilesController < ApplicationController
  include PinThrottling

  allow_unauthenticated_access only: %i[select set]
  throttle_pin_attempts only: :set

  def select
    household = Household.installation
    @family_members = household ? household.family_members.order(:id) : []
  end

  def set
    # Scoped to the installation rather than FamilyMember.find, which was a
    # global finder taking a user-supplied id. On a single-household install the
    # two return the same row; with a second household the unscoped version is
    # account takeover by id enumeration.
    member = Household.installation&.family_members&.find(params[:id])
    raise ActiveRecord::RecordNotFound if member.nil?

    if member.requires_pin? && params[:pin].blank?
      flash[:alert] = "This profile is protected by a PIN."
      redirect_to select_profile_path(pin_member_id: member.id) and return
    end

    if member.requires_pin? && !member.verify_pin(params[:pin])
      log_pin_failure(member)
      flash[:alert] = "Incorrect 4-digit PIN for #{member.name}."
      redirect_to select_profile_path(pin_member_id: member.id) and return
    end

    start_new_session_for(member)
    target_url = after_authentication_url
    redirect_to target_url, notice: "Welcome to the kitchen, #{member.name}! 🍳"
  end
end
