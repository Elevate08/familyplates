# frozen_string_literal: true

require "webauthn"

class PasskeysController < ApplicationController
  allow_unauthenticated_access only: %i[index registration_options create destroy authentication_options callback]
  before_action :require_user_for_management, only: %i[index registration_options create destroy]
  before_action :forbid_kiosk_access, only: %i[index registration_options create destroy]

  # GET /passkeys
  def index
    @passkeys = current_user.passkeys.order(created_at: :desc)
    @household = current_household || current_user.households.first || Household.installation
  end

  # POST /passkeys/registration_options
  def registration_options
    options = relying_party.options_for_registration(
      user: {
        id: current_user.webauthn_id,
        name: current_user.email,
        display_name: current_user.email
      },
      exclude: current_user.passkeys.pluck(:external_id)
    )

    session[:webauthn_challenge] = options.challenge
    render json: options
  end

  # POST /passkeys
  def create
    challenge = session.delete(:webauthn_challenge)
    if challenge.blank?
      return render json: { error: "Registration session expired. Please try again." }, status: :unprocessable_entity
    end

    credential_params = params[:credential]&.as_json || params.as_json

    begin
      verified = relying_party.verify_registration(credential_params, challenge)

      passkey = current_user.passkeys.create!(
        external_id: verified.id,
        public_key: verified.public_key,
        sign_count: verified.sign_count,
        nickname: params[:nickname].presence || "Passkey #{current_user.passkeys.count + 1}"
      )

      respond_to do |format|
        format.html { redirect_to passkeys_path, notice: "Passkey '#{passkey.label}' registered successfully." }
        format.json { render json: { ok: true, id: passkey.id, label: passkey.label }, status: :created }
      end
    rescue WebAuthn::Error => e
      respond_to do |format|
        format.html { redirect_to passkeys_path, alert: "Failed to register passkey: #{e.message}" }
        format.json { render json: { error: "Failed to register passkey: #{e.message}" }, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /passkeys/:id
  def destroy
    passkey = current_user.passkeys.find(params[:id])
    passkey.destroy

    redirect_to passkeys_path, notice: "Passkey removed."
  end

  # POST /passkeys/authentication_options
  def authentication_options
    allow_credentials = if params[:email].present?
      User.find_by(email: params[:email])&.passkeys&.pluck(:external_id) || []
    else
      []
    end

    options = relying_party.options_for_authentication(
      allow: allow_credentials
    )

    session[:webauthn_challenge] = options.challenge
    render json: options
  end

  # POST /passkeys/callback
  def callback
    challenge = session.delete(:webauthn_challenge)
    if challenge.blank?
      return render json: { error: "Authentication session expired. Please try again." }, status: :unprocessable_entity
    end

    credential_params = params[:credential]&.as_json || params.as_json
    passkey = Passkey.find_by(external_id: credential_params["id"])

    if passkey.nil?
      return render json: { error: "Passkey not recognized. Please sign in with your email or password." }, status: :unprocessable_entity
    end

    begin
      verified = relying_party.verify_authentication(
        credential_params,
        challenge,
        public_key: passkey.public_key,
        sign_count: passkey.sign_count
      )

      passkey.update_sign_count!(verified.sign_count)
      start_new_session_for_user(passkey.user)

      render json: { ok: true, redirect_url: after_authentication_url }, status: :ok
    rescue WebAuthn::Error => e
      render json: { error: "Passkey authentication failed: #{e.message}" }, status: :unprocessable_entity
    end
  end

  private

  def require_user_for_management
    unless current_user
      session[:return_to_after_authenticating] = request.url
      redirect_to new_session_path, alert: "Please sign in to manage passkeys."
    end
  end

  def forbid_kiosk_access
    if Current.session&.kiosk?
      redirect_to root_path, alert: "Kiosk devices cannot manage passkeys."
    end
  end

  def relying_party
    allowed = [
      request.origin,
      "http://#{request.host_with_port}",
      "https://#{request.host_with_port}",
      "http://#{request.host}",
      "https://#{request.host}",
      "http://localhost:3000",
      "http://127.0.0.1:3000",
      "http://www.example.com",
      "https://www.example.com"
    ].compact.uniq

    WebAuthn::RelyingParty.new(
      name: "FamilyPlates",
      id: request.host,
      allowed_origins: allowed
    )
  end
end
