class PreferencesController < ApplicationController
  before_action :set_family_member

  def edit
    @household = current_household
    @family_members = @household ? @household.family_members.order(:id) : []
  end

  def update
    if @family_member.update(preference_params)
      # Ensure current active session reflects updated member
      Current.family_member = @family_member
      redirect_to edit_preferences_path, notice: "Your preferences were saved successfully! 🎨"
    else
      @household = current_household
      @family_members = @household ? @household.family_members.order(:id) : []
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
    if @family_member.admin?
      params.require(:family_member).permit(:name, :avatar_color, :avatar_icon, :pin)
    else
      params.require(:family_member).permit(:name, :avatar_color, :avatar_icon)
    end
  end
end
