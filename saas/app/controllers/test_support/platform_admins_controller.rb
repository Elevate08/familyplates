module TestSupport
  class PlatformAdminsController < ActionController::Base
    skip_forgery_protection

    before_action { head :forbidden unless Rails.env.test? }

    # The platform operator is a separate account with its own session cookie,
    # not a household profile, so the household sign-in in TestSupportController
    # cannot stand in.
    def create
      admin = PlatformAdminAccount.find_or_create_by!(email: "crawler@platform.test") do |account|
        account.password = SecureRandom.hex(16)
      end
      session_record = admin.sessions.create!(ip_address: request.remote_ip, user_agent: request.user_agent)

      cookies.signed.permanent[:platform_admin_session_token] = {
        value: session_record.token, httponly: true, same_site: :lax, secure: request.ssl?
      }

      render json: { status: "ok", platform_admin_id: admin.id }
    end
  end
end
