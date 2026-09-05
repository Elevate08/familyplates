class PreferencesController < ApplicationController
  include PinThrottling

  before_action :set_family_member
  throttle_pin_attempts only: :update

  def edit
    @household = current_household
    @family_members = @household ? @household.family_members.order(:created_at, :id) : []
  end

  def update
    if @family_member.requires_pin?
      current_pin = params[:current_pin].presence || params.dig(:family_member, :current_pin).presence
      if current_pin.blank?
        @family_member.assign_attributes(preference_params.except(:pin))
        @family_member.errors.add(:base, "Please enter your current 4-digit PIN to confirm changes.")
        @household = current_household
        @family_members = @household ? @household.family_members.order(:created_at, :id) : []
        render :edit, status: :unprocessable_entity
        return
      elsif !@family_member.verify_pin(current_pin)
        log_pin_failure(@family_member)
        @family_member.assign_attributes(preference_params.except(:pin))
        @family_member.errors.add(:base, "Incorrect 4-digit PIN. Changes were not saved.")
        @household = current_household
        @family_members = @household ? @household.family_members.order(:created_at, :id) : []
        render :edit, status: :unprocessable_entity
        return
      end
    end

    if @family_member.update(preference_params)
      # Ensure current active session reflects updated member
      Current.family_member = @family_member
      redirect_to edit_preferences_path, notice: "Your preferences were saved successfully! 🎨"
    else
      @household = current_household
      @family_members = @household ? @household.family_members.order(:created_at, :id) : []
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_family_member
    @family_member = current_family_member
    unless @family_member
      redirect_to select_profile_path, alert: "Please select a family profile first."
    end
  end

  def preference_params
    if @family_member.admin? && !Current.session&.kiosk?
      params.require(:family_member).permit(:name, :avatar_color, :avatar_icon, :pin)
    else
      params.require(:family_member).permit(:name, :avatar_color, :avatar_icon)
    end
  end
end
