module PlatformAdmin
  class AuditEventsController < BaseController
    def index
      @category = params[:category].presence || "all"
      @action_name = params[:action_name].presence
      @admin_id = params[:admin_id].presence
      @query = params[:q].presence
      @hide_views = params[:hide_views] == "1"

      scope = PlatformAuditEvent.includes(:platform_admin).order(created_at: :desc, id: :desc)
      scope = scope.for_category(@category) if @category != "all"
      scope = scope.without_views if @hide_views && @category != "changes"
      scope = scope.where(action: @action_name) if @action_name.present?
      scope = scope.where(platform_admin_id: @admin_id) if @admin_id.present?
      scope = scope.search(@query) if @query.present?

      @total_count = PlatformAuditEvent.count
      @filtered_count = scope.count
      @events = scope.limit(100)

      @available_actions = PlatformAuditEvent.distinct.order(:action).pluck(:action)
      @platform_admins = PlatformAdminAccount.order(:email)
      @filters_active = @category != "all" || @action_name.present? || @admin_id.present? || @query.present? || @hide_views
    end
  end
end
