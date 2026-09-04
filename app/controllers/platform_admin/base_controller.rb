module PlatformAdmin
  class BaseController < ActionController::Base
    include PlatformAdminAuthentication

    allow_browser versions: :modern

    helper_method :record_platform_audit!

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
