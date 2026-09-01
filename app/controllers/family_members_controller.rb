class FamilyMembersController < ApplicationController
  include PinThrottling

  throttle_pin_attempts only: :switch
  before_action :set_family_member, only: %i[switch]

  def index
    @family_members = current_household.family_members.order(:created_at)
  end

  def switch
    if @family_member.requires_pin? && !@family_member.verify_pin(params[:pin])
      log_pin_failure(@family_member)
      redirect_to select_profile_path(pin_member_id: @family_member.id), alert: "Please enter the 4-digit PIN for #{@family_member.name}."
      return
    end

    start_new_session_for(@family_member)

    redirect_back fallback_location: root_path, notice: "Now browsing as #{@family_member.name}"
  end

  private

  def set_family_member
    @family_member = current_household.family_members.find(params[:id])
  end
end
