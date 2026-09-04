module PlatformAdmin
  class SessionsController < BaseController
    allow_platform_admin_unauthenticated_access only: %i[new create]

    def new
    end

    def create
      email = params[:email].to_s.strip.downcase
      admin = PlatformAdminAccount.find_by(email: email)

      if admin&.active? && admin.authenticate(params[:password].to_s) && admin.valid_totp?(params[:otp_code])
        admin.update!(last_signed_in_at: Time.current)
        start_platform_admin_session_for(admin)
        redirect_to platform_admin_root_path, notice: "Signed in to the platform console."
      else
        BCrypt::Password.create("dummy", cost: BCrypt::Engine::MIN_COST)
        flash.now[:alert] = "Invalid email, password, or verification code."
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      terminate_platform_admin_session
      redirect_to new_platform_admin_session_path, notice: "Signed out of the platform console.", status: :see_other
    end
  end
end
