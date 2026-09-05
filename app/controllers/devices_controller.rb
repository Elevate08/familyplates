class DevicesController < ApplicationController
  allow_unauthenticated_access only: %i[index destroy destroy_all]
  before_action :require_signed_in_user
  before_action :forbid_kiosk_access

  def index
    @sessions = current_user.sessions.order(last_active_at: :desc)
  end

  def destroy
    session_record = current_user.sessions.find(params[:id])
    was_current = (session_record == Current.session)
    session_kind = session_record.kind
    session_record.destroy

    if was_current
      terminate_session
      redirect_to signed_out_path(kind: session_kind), notice: "You have signed out from this device."
    else
      redirect_to devices_path, notice: "Device access revoked."
    end
  end

  def destroy_all
    current_user.sessions.where.not(id: Current.session&.id).destroy_all
    redirect_to devices_path, notice: "All other devices have been signed out."
  end

  private

  def forbid_kiosk_access
    if Current.session&.kiosk?
      redirect_to root_path, alert: "Kiosk devices cannot manage connected devices."
    end
  end

  def require_signed_in_user
    unless current_user
      redirect_to new_session_path, alert: "Please sign in to manage connected devices."
    end
  end
end
