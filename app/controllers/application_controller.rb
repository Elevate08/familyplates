class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :household_today, :household_now

  private

  # "Today" and "now" as the kitchen sees them. Date.current is the server's
  # day, and the server runs on UTC, so after 7pm in the Americas it is already
  # tomorrow - which is how the meal plan came to highlight the wrong column and
  # Cook Mode came to look at the wrong day's meals.
  def household_today
    current_household&.today || Date.current
  end

  def household_now
    current_household&.current_time || Time.current
  end

  def track_activity(event_type, target: nil, metadata: {}, source: "web")
    ActivityEvent.track!(
      household: current_household,
      actor: current_family_member,
      event_type: event_type,
      target: target,
      source: source,
      metadata: metadata
    )
  end

  def require_admin
    if Current.session&.kiosk?
      respond_to do |format|
        format.html do
          redirect_back fallback_location: root_path, alert: "Kiosk devices cannot access household settings or admin tools."
        end
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("flash-messages", partial: "shared/flash", locals: { alert: "Kiosk devices cannot access household settings or admin tools." }), status: :forbidden
        end
        format.json do
          render json: { error: "Kiosk devices cannot access household settings or admin tools." }, status: :forbidden
        end
      end
      return
    end

    return if current_family_member&.admin?

    respond_to do |format|
      format.html do
        redirect_back fallback_location: root_path, alert: "Access restricted to household organizers / admins."
      end
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("flash-messages", partial: "shared/flash", locals: { alert: "Access restricted to household organizers / admins." }), status: :forbidden
      end
      format.json do
        render json: { error: "Access restricted to household organizers / admins." }, status: :forbidden
      end
    end
  end
end
