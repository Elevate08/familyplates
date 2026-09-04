module PlatformAdminAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :set_current_platform_admin
    before_action :require_platform_admin
    helper_method :current_platform_admin, :platform_admin_authenticated?
  end

  class_methods do
    def allow_platform_admin_unauthenticated_access(**options)
      skip_before_action :require_platform_admin, **options
    end
  end

  private

  def current_platform_admin
    Current.platform_admin
  end

  def platform_admin_authenticated?
    Current.platform_admin.present?
  end

  def set_current_platform_admin
    token = cookies.signed[:platform_admin_session_token]
    return if token.blank?

    session_record = PlatformAdminSession.includes(:platform_admin).find_by(token: token)
    if session_record && !session_record.expired? && session_record.platform_admin.active?
      session_record.resume(user_agent: request.user_agent, ip_address: request.remote_ip)
      Current.platform_admin_session = session_record
      Current.platform_admin = session_record.platform_admin
    else
      session_record&.destroy
      cookies.delete(:platform_admin_session_token)
    end
  end

  def require_platform_admin
    return if current_platform_admin

    redirect_to new_platform_admin_session_path, alert: "Platform-admin authentication required."
  end

  def start_platform_admin_session_for(admin)
    session_record = admin.sessions.create!(
      token: SecureRandom.hex(32),
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      last_active_at: Time.current
    )
    cookies.signed.permanent[:platform_admin_session_token] = {
      value: session_record.token,
      httponly: true,
      same_site: :strict,
      secure: request.ssl?
    }
    Current.platform_admin_session = session_record
    Current.platform_admin = admin
  end

  def terminate_platform_admin_session
    token = cookies.signed[:platform_admin_session_token]
    PlatformAdminSession.find_by(token: token)&.destroy if token.present?
    cookies.delete(:platform_admin_session_token)
    Current.platform_admin_session = nil
    Current.platform_admin = nil
  end
end
