module PlatformAdmin
  class AuditEventsController < BaseController
    def index
      @events = PlatformAuditEvent.includes(:platform_admin)
        .order(created_at: :desc, id: :desc)
        .limit(100)
    end
  end
end
