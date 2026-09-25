# frozen_string_literal: true

class DevicePairingsController < ApplicationController
  allow_unauthenticated_access only: %i[index new device_authorization token verify approve deny]
  skip_before_action :verify_authenticity_token, only: %i[device_authorization token]

  def index
    if params[:user_code].present?
      redirect_to verify_pair_path(user_code: params[:user_code]) and return
    end

    require_signed_in_user("Please sign in to pair or approve a device.")
  end

  def new
    @grant = DeviceGrant.create!(
      kind: requested_device_kind,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
    @verification_uri = pair_url
    @verification_uri_complete = verify_pair_url(user_code: @grant.user_code)
  end

  def device_authorization
    @grant = DeviceGrant.create!(
      kind: requested_device_kind,
      client_name: params[:client_name],
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )

    render json: {
      device_code: @grant.device_code,
      user_code: @grant.user_code,
      verification_uri: pair_url,
      verification_uri_complete: verify_pair_url(user_code: @grant.user_code),
      expires_in: @grant.expires_in_seconds,
      interval: @grant.interval_seconds
    }, status: :ok
  end

  def token
    grant = DeviceGrant.find_by(device_code: params[:device_code])
    return render_grant_error("invalid_grant", "Unknown device code.") if grant.nil?

    if grant.expired?
      grant.update_columns(status: "expired") if grant.pending?
      return render_grant_error("expired_token", "The device code has expired.")
    end

    return render_grant_error("access_denied", "Pairing was denied.") if grant.denied?
    return render_grant_error("slow_down", "Polling too frequently. Please wait #{grant.interval_seconds} seconds.") if grant.polling_too_fast?

    grant.update_columns(last_polled_at: Time.current)

    if grant.pending?
      render_grant_error("authorization_pending", "Waiting for user approval.")
    elsif grant.approved?
      redeem_approved_grant(grant)
    else
      render_grant_error("invalid_grant", "Grant has been revoked or invalidated.")
    end
  end

  def verify
    return unless require_signed_in_user("Please sign in to approve device pairing.")
    return unless require_non_kiosk_approver

    @user_code = DeviceGrant.normalize_user_code(params[:user_code])
    @grant = DeviceGrant.find_by_user_code(@user_code)

    if @grant.nil?
      redirect_to pair_path, alert: "Pairing code not found. Please check the code and try again." and return
    end

    if @grant.expired?
      redirect_to pair_path, alert: "This pairing code has expired. Please refresh the device screen." and return
    end

    if @grant.approved? || @grant.redeemed?
      redirect_to devices_path, notice: "This device is already paired." and return
    end

    if @grant.denied?
      redirect_to pair_path, alert: "This pairing code was previously denied." and return
    end

    @household = pairing_household
  end

  def approve
    return unless require_signed_in_user("Please sign in to approve device pairing.")
    return unless require_non_kiosk_approver

    @grant = DeviceGrant.find_by_user_code(params[:user_code])

    if @grant.nil? || !@grant.pending?
      redirect_to pair_path, alert: "Pairing code is invalid or has expired." and return
    end

    target_household = pairing_household
    target_kind = params[:kind].presence || @grant.kind.presence || "kiosk"

    @grant.approve!(by: current_user, household: target_household, kind: target_kind)

    respond_to do |format|
      format.html do
        redirect_to devices_path, notice: "Device successfully paired as #{target_kind}."
      end
      format.json do
        render json: { ok: true, message: "Device paired successfully." }, status: :ok
      end
    end
  end

  def deny
    if current_user.nil? || Current.session&.kiosk?
      redirect_to new_session_path, alert: "Unauthorized." and return
    end

    @grant = DeviceGrant.find_by_user_code(params[:user_code])
    @grant&.deny! if @grant&.pending?

    redirect_to pair_path, notice: "Device pairing request denied."
  end

  private

  def require_signed_in_user(alert)
    return true if current_user.present?

    session[:return_to_after_authenticating] = request.url
    redirect_to new_session_path, alert: alert
    false
  end

  def require_non_kiosk_approver
    return true unless Current.session&.kiosk?

    redirect_to root_path, alert: "Kiosk devices cannot approve new device pairings."
    false
  end

  def requested_device_kind
    params[:kind] == "browser" ? "browser" : "kiosk"
  end

  def pairing_household
    current_household || current_user.households.first || Household.installation
  end

  def redeem_approved_grant(grant)
    session_record = grant.session
    if session_record.nil? || session_record.expired?
      return render_grant_error("invalid_grant", "Associated session is expired or invalid.")
    end

    raw_token = grant.redeem!
    return render_grant_error("invalid_grant", "This pairing has already been completed.") if raw_token.nil?

    write_permanent_signed_cookie(:session_token, raw_token)
    write_permanent_signed_cookie(:device_kind, session_record.kind)

    render json: {
      access_token: raw_token,
      token_type: "Bearer",
      session_token: raw_token,
      kind: session_record.kind,
      redirect_url: root_url
    }, status: :ok
  end

  def render_grant_error(error, description)
    render json: { error: error, error_description: description }, status: :bad_request
  end
end
