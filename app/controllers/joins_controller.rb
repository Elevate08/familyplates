class JoinsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  def new
  end

  def create
    code = params[:join_code].to_s.strip.upcase
    @household = Household.find_by(join_code: code)

    unless @household
      flash.now[:alert] = "Invalid join code. Please check the code and try again."
      render :new, status: :unprocessable_entity and return
    end

    unless current_user
      session[:pending_join_code] = code
      session[:return_to_after_authenticating] = join_path
      redirect_to new_session_path, notice: "Join code accepted for #{@household.name}. Please sign in to complete joining." and return
    end

    existing_member = current_user.family_members.find_by(household: @household)
    if existing_member
      start_new_session_for(existing_member)
      redirect_to root_path, notice: "You are already part of #{@household.name}!"
    else
      name = params[:name].presence || current_user.email.split("@").first.capitalize
      member = @household.family_members.create!(
        name: name,
        user: current_user,
        avatar_color: FamilyMember::AVATAR_COLORS.sample,
        avatar_icon: FamilyMember::AVATAR_ICONS.sample
      )
      start_new_session_for(member)
      redirect_to root_path, notice: "Welcome to #{@household.name}!"
    end
  end
end
