# frozen_string_literal: true

class DevicePairingsController < ApplicationController
  allow_unauthenticated_access only: %i[index new device_authorization token verify approve deny]
  skip_before_action :verify_authenticity_token, only: %i[device_authorization token]

  # GET /pair
  def index
    if params[:user_code].present?
      redirect_to verify_pair_path(user_code: params[:user_code]) and return
    end

    if current_user.nil?
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path, alert: "Please sign in to pair or approve a device." and return
    end
  end

  # GET /pair/new
  def new
    requested_kind = params[:kind] == "browser" ? "browser" : "kiosk"
    @grant = DeviceGrant.create!(
      kind: requested_kind,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
    @verification_uri = pair_url
    @verification_uri_complete = verify_pair_url(user_code: @grant.user_code)
  end

  # POST /pair/device_authorization (RFC 8628 Section 3.1)
  def device_authorization
    requested_kind = params[:kind] == "browser" ? "browser" : "kiosk"
    @grant = DeviceGrant.create!(
      kind: requested_kind,
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

  # POST /pair/token (RFC 8628 Section 3.4 & 3.5)
  def token
    grant = DeviceGrant.find_by(device_code: params[:device_code])

    if grant.nil?
      return render json: { error: "invalid_grant", error_description: "Unknown device code." }, status: :bad_request
    end

    if grant.expired?
      grant.update_columns(status: "expired") if grant.pending?
      return render json: { error: "expired_token", error_description: "The device code has expired." }, status: :bad_request
    end

    if grant.denied?
      return render json: { error: "access_denied", error_description: "Pairing was denied." }, status: :bad_request
    end

    if grant.polling_too_fast?
      return render json: { error: "slow_down", error_description: "Polling too frequently. Please wait #{grant.interval_seconds} seconds." }, status: :bad_request
    end

    grant.update_columns(last_polled_at: Time.current)

    if grant.pending?
      render json: { error: "authorization_pending", error_description: "Waiting for user approval." }, status: :bad_request
    elsif grant.approved?
      session_record = grant.session
      if session_record.nil? || session_record.expired?
        return render json: { error: "invalid_grant", error_description: "Associated session is expired or invalid." }, status: :bad_request
      end

      # Establish session cookie on the browser
      cookies.signed.permanent[:session_token] = {
        value: session_record.token,
        httponly: true,
        same_site: :lax,
        secure: request.ssl?
      }

      render json: {
        access_token: session_record.token,
        token_type: "Bearer",
        session_token: session_record.token,
        kind: session_record.kind,
        redirect_url: root_url
      }, status: :ok
    else
      render json: { error: "invalid_grant", error_description: "Grant has been revoked or invalidated." }, status: :bad_request
    end
  end

  # GET /pair/verify?user_code=...
  def verify
    if current_user.nil?
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path, alert: "Please sign in to approve device pairing." and return
    end

    if Current.session&.kiosk?
      redirect_to root_path, alert: "Kiosk devices cannot approve new device pairings." and return
    end

    @user_code = DeviceGrant.normalize_user_code(params[:user_code])
    @grant = DeviceGrant.find_by_user_code(@user_code)

    if @grant.nil?
      redirect_to pair_path, alert: "Pairing code not found. Please check the code and try again." and return
    end

    if @grant.expired?
      redirect_to pair_path, alert: "This pairing code has expired. Please refresh the device screen." and return
    end

    if @grant.approved?
      redirect_to devices_path, notice: "This device is already paired." and return
    end

    if @grant.denied?
      redirect_to pair_path, alert: "This pairing code was previously denied." and return
    end

    @household = current_household || current_user.households.first || Household.installation
  end

  # POST /pair/approve
  def approve
    if current_user.nil?
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path, alert: "Please sign in to approve device pairing." and return
    end

    if Current.session&.kiosk?
      redirect_to root_path, alert: "Kiosk devices cannot approve new device pairings." and return
    end

    @grant = DeviceGrant.find_by_user_code(params[:user_code])

    if @grant.nil? || !@grant.pending?
      redirect_to pair_path, alert: "Pairing code is invalid or has expired." and return
    end

    target_household = current_household || current_user.households.first || Household.installation
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

  # POST /pair/deny
  def deny
    if current_user.nil? || Current.session&.kiosk?
      redirect_to new_session_path, alert: "Unauthorized." and return
    end

    @grant = DeviceGrant.find_by_user_code(params[:user_code])
    @grant&.deny! if @grant&.pending?

    redirect_to pair_path, notice: "Device pairing request denied."
  end
end
