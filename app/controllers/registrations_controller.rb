class RegistrationsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  before_action :ensure_registration_available

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

      # Create default family member profile (Admin requires 4-digit PIN)
      initial_member_name = params[:family_member_name].presence || @user.email_address.split("@").first.capitalize
      initial_pin = params[:family_member_pin].presence || "1234"
      admin_member = @household.family_members.create!(
        name: initial_member_name,
        role: "admin",
        avatar_color: "#3B82F6",
        avatar_icon: "chef-hat",
        pin: initial_pin
      )

      start_new_session_for(@user)
      cookies.signed.permanent[:active_family_member_id] = admin_member.id
      Current.family_member = admin_member
      redirect_to onboarding_recipes_path, notice: "Welcome to FamilyPlates! Let's get your family kitchen set up."
    end
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    render :new, status: :unprocessable_entity
  end

  private

  def ensure_registration_available
    return unless Household.exists?

    if authenticated?
      redirect_to root_path, alert: "Your family kitchen is already set up."
    else
      redirect_to new_session_path, alert: "This kitchen is already configured. Please sign in."
    end
  end

  def household_params
    params.require(:household).permit(:name)
  end

  def user_params
    params.require(:user).permit(:email_address, :password, :password_confirmation)
  end
end
