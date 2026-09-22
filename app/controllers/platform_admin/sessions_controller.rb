module PlatformAdmin
  class SessionsController < BaseController
    allow_platform_admin_unauthenticated_access only: %i[new create]

    def new
    end

    def create
      email = params[:email].to_s.strip.downcase
      admin = PlatformAdminAccount.find_by(email: email)

      if admin&.active?
        password_ok = admin.authenticate(params[:password].to_s)
      else
        # Spend the same bcrypt work as a real password check, so an unknown or
        # deactivated email is not cheaper to probe than a wrong password.
        BCrypt::Password.create("dummy", cost: password_hash_cost)
        password_ok = false
      end

      if password_ok && admin.valid_totp?(params[:otp_code])
        admin.update!(last_signed_in_at: Time.current)
        start_platform_admin_session_for(admin)
        record_platform_audit!("platform_admin.signed_in", metadata: { email: admin.email })
        redirect_to platform_admin_root_path, notice: "Signed in to the platform console.", status: :see_other
      else
        record_platform_audit!("platform_admin.sign_in_failed", metadata: { email: email.presence })
        flash.now[:alert] = "Invalid email, password, or verification code."
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      terminate_platform_admin_session
      redirect_to new_platform_admin_session_path, notice: "Signed out of the platform console.", status: :see_other
    end

    private

    def password_hash_cost
      ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST : BCrypt::Engine.cost
    end
  end
end
