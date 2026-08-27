class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  def new
    redirect_to root_path if authenticated?
    @household = Household.new
    @user = User.new
  end

  def create
    ActiveRecord::Base.transaction do
      @household = Household.new(name: household_params[:name].presence || "Our Family")
      @household.save!

      @user = @household.users.build(user_params)
      @user.save!

      # Create default family member profile
      initial_member_name = params[:family_member_name].presence || @user.email_address.split("@").first.capitalize
      @household.family_members.create!(
        name: initial_member_name,
        role: "admin",
        avatar_color: "#3B82F6",
        avatar_icon: "chef-hat"
      )

      start_new_session_for(@user)
      redirect_to onboarding_recipes_path, notice: "Welcome to MealHub! Let's get your family kitchen set up."
    end
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :new, status: :unprocessable_entity
  end

  private

  def household_params
    params.require(:household).permit(:name)
  end

  def user_params
    params.require(:user).permit(:email_address, :password, :password_confirmation)
  end
end
