module PlatformAdmin
  class BaseController < ActionController::Base
    include PlatformAdminAuthentication

    layout "application"

    allow_browser versions: :modern

    helper_method :record_platform_audit!
    helper_method :current_family_member, :current_household, :authenticated?

    def current_family_member
      nil
    end

    def current_household
      nil
    end

    def authenticated?
      false
    end

    def record_platform_audit!(action, target: nil, metadata: {})
      PlatformAuditEvent.record!(
        action: action,
        actor: current_platform_admin,
        target: target,
        metadata: metadata,
        request: request
      )
    end
  end
end
