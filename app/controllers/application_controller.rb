class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

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
