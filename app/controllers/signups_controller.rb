# frozen_string_literal: true

class SignupsController < ApplicationController
  allow_unauthenticated_access only: %i[new create verify submit_verify]

  def new
    if authenticated? && current_household&.onboarded?
      redirect_to root_path and return
    end
  end

  def create
    household_name = params[:household_name].to_s.strip
    organizer_name = params[:organizer_name].to_s.strip
    email = params[:email].to_s.strip.downcase
    pin = params[:pin].to_s.strip.presence || "1234"
    avatar_color = params[:avatar_color].to_s.strip.presence || FamilyMember::DEFAULT_COLOR
    avatar_icon = params[:avatar_icon].to_s.strip.presence || FamilyMember::DEFAULT_ICON

    if household_name.blank? || organizer_name.blank? || email.blank?
      flash.now[:alert] = "Please provide your household name, your name, and a valid email address."
      render :new, status: :unprocessable_entity and return
    end

    unless email.match?(URI::MailTo::EMAIL_REGEXP)
      flash.now[:alert] = "Please enter a valid email address."
      render :new, status: :unprocessable_entity and return
    end

    if pin.present? && !pin.match?(/\A\d{4}\z/)
      flash.now[:alert] = "Security PIN must be exactly 4 digits."
      render :new, status: :unprocessable_entity and return
    end

    if FamilyPlates.config.hosted?
      if current_user.present? && current_user.email == email
        household = Household.create!(name: household_name)
        organizer = household.family_members.create!(
          name: organizer_name,
          role: "admin",
          user: current_user,
          pin: pin,
          avatar_color: avatar_color,
          avatar_icon: avatar_icon
        )
        start_new_session_for_user(current_user)
        start_new_session_for(organizer)
        redirect_to onboarding_recipes_path, notice: "Welcome to #{household.name}, #{organizer.name}! Let's set up your recipes." and return
      end

      FamilyPlates::OutboundEmail.validate!
      magic_code = MagicCode.create!(email: email)
      AuthenticationMailer.verification_code(magic_code).deliver_later
      flash[:magic_link_code] = magic_code.code if Rails.env.development?

      session[:pending_signup] = {
        "household_name" => household_name,
        "organizer_name" => organizer_name,
        "email" => email,
        "pin" => pin,
        "avatar_color" => avatar_color,
        "avatar_icon" => avatar_icon
      }
      redirect_to verify_signup_path, notice: "We sent a 6-character verification code to #{email}."
    else
      # Appliance mode: instant signup
      user = User.find_by(email: email) || User.create!(email: email, password: params[:password].presence || SecureRandom.hex(16))
      household = Household.create!(name: household_name)
      organizer = household.family_members.create!(
        name: organizer_name,
        role: "admin",
        user: user,
        pin: pin,
        avatar_color: avatar_color,
        avatar_icon: avatar_icon
      )
      start_new_session_for_user(user)
      start_new_session_for(organizer)
      redirect_to onboarding_recipes_path, notice: "Welcome to #{household.name}, #{organizer.name}! Let's set up your recipes."
    end
  end

  def verify
    @pending = session[:pending_signup]
    unless @pending
      redirect_to new_signup_path, alert: "Please start your signup again." and return
    end
    @email = @pending["email"]
  end

  def submit_verify
    @pending = session[:pending_signup]
    unless @pending
      redirect_to new_signup_path, alert: "Please start your signup again." and return
    end

    code = params[:code].to_s.strip.upcase
    email = @pending["email"].to_s.strip.downcase
    magic_code = MagicCode.active.find_by(email: email, code: code)

    if magic_code
      magic_code.destroy
      session.delete(:pending_signup)

      user = User.find_by(email: email) || User.create!(email: email)
      household = Household.create!(name: @pending["household_name"])
      organizer = household.family_members.create!(
        name: @pending["organizer_name"],
        role: "admin",
        user: user,
        pin: @pending["pin"].presence || "1234",
        avatar_color: @pending["avatar_color"].presence || FamilyMember::DEFAULT_COLOR,
        avatar_icon: @pending["avatar_icon"].presence || FamilyMember::DEFAULT_ICON
      )

      start_new_session_for_user(user)
      start_new_session_for(organizer)
      redirect_to onboarding_recipes_path, notice: "Email verified! Welcome to #{household.name}, #{organizer.name}! Let's choose your starter recipes."
    else
      BCrypt::Password.create("dummy", cost: BCrypt::Engine::MIN_COST)
      @email = email
      flash.now[:alert] = "Invalid or expired verification code."
      render :verify, status: :unprocessable_entity
    end
  end
end
