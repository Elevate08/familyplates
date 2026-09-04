class SessionsController < ApplicationController
  include LoginThrottling

  allow_unauthenticated_access only: %i[new create verify submit_verify destroy]
  throttle_login_attempts only: %i[create submit_verify]

  after_action :ensure_development_magic_link_not_leaked, only: %i[create]

  def new
    if authenticated? && current_user
      redirect_to root_path and return
    end
  end

  def create
    if FamilyPlates.config.hosted?
      create_hosted_session
    else
      create_appliance_session
    end
  end

  def verify
    @email = params[:email].presence || session[:pending_auth_email]
  end

  def submit_verify
    email = (params[:email].presence || session[:pending_auth_email]).to_s.strip.downcase
    code = params[:code].to_s.strip.upcase
    magic_code = MagicCode.active.find_by(email: email, code: code)

    if magic_code
      user = magic_code.user || User.find_by(email: email)
      magic_code.destroy
      session.delete(:pending_auth_email)

      if user
        start_new_session_for_user(user)
        redirect_to after_authentication_url, notice: "Signed in successfully."
      else
        BCrypt::Password.create("dummy", cost: BCrypt::Engine::MIN_COST)
        flash.now[:alert] = "Invalid or expired code."
        render :verify, status: :unprocessable_entity
      end
    else
      BCrypt::Password.create("dummy", cost: BCrypt::Engine::MIN_COST)
      flash.now[:alert] = "Invalid or expired code."
      render :verify, status: :unprocessable_entity
    end
  end

  def destroy
    terminate_session
    redirect_to select_profile_path, notice: "Signed out successfully.", status: :see_other
  end

  private

  def create_appliance_session
    email = params[:email].to_s.strip.downcase
    user = User.find_by(email: email)

    if user&.password_digest.present? && user.authenticate(params[:password].to_s)
      start_new_session_for_user(user)
      redirect_to after_authentication_url, notice: "Signed in successfully."
    else
      BCrypt::Password.create("dummy", cost: BCrypt::Engine::MIN_COST)
      flash.now[:alert] = "Invalid email or password."
      render :new, status: :unprocessable_entity
    end
  end

  def create_hosted_session
    FamilyPlates::OutboundEmail.validate!
    email = params[:email].to_s.strip.downcase
    user = User.find_by(email: email)

    if user
      magic_code = user.magic_codes.create!(email: email)
      AuthenticationMailer.magic_code(magic_code).deliver_later
      flash[:magic_link_code] = magic_code.code if Rails.env.development?
    else
      _fake = MagicCode.for_unknown_email(email)
      BCrypt::Password.create("dummy", cost: BCrypt::Engine::MIN_COST)
    end

    session[:pending_auth_email] = email
    redirect_to verify_session_path, notice: "If an account exists for that email, a 6-character code has been sent."
  end

  def ensure_development_magic_link_not_leaked
    if flash[:magic_link_code].present? && !Rails.env.development?
      raise "Security Violation: Authentication code leaked into flash outside development environment"
    end
  end
end
