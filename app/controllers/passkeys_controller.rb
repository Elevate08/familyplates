# frozen_string_literal: true

require "webauthn"

class PasskeysController < ApplicationController
  class NotConfigured < StandardError; end

  LOCAL_ORIGINS = [
    "http://localhost:3000",
    "http://127.0.0.1:3000",
    "http://www.example.com",
    "https://www.example.com"
  ].freeze

  # Production with APP_HOST trusts only that public host, never the
  # request's Origin or Host header, which a client controls. Only https when
  # the app is hosted, forces SSL or is told it sits behind TLS (ASSUME_SSL);
  # otherwise an appliance's proxy may terminate TLS without saying so, so
  # both schemes are allowed for that one host. An appliance without APP_HOST (a LAN install) uses the host
  # it was reached by, never the Origin header: the browser binds a passkey
  # to the page's real domain, so a forged Host cannot help a phishing page.
  # Hosted mode always has APP_HOST; without it there is no relying party.
  # Elsewhere the request host and local development origins are accepted.
  def self.relying_party_settings(request = nil, environment: Rails.env)
    if environment.production?
      host = FamilyPlates.public_host
      if host.present?
        config = Rails.application.config
        https_only = FamilyPlates.config.hosted? || config.force_ssl || config.assume_ssl
        [ host.split(":").first, https_only ? [ "https://#{host}" ] : [ "https://#{host}", "http://#{host}" ] ]
      elsif request && !FamilyPlates.config.hosted?
        [ request.host, [ "http://#{request.host_with_port}", "https://#{request.host_with_port}" ] ]
      else
        [ nil, [] ]
      end
    else
      origins = LOCAL_ORIGINS.dup
      if request
        origins.concat([ request.origin, "http://#{request.host_with_port}", "https://#{request.host_with_port}",
                         "http://#{request.host}", "https://#{request.host}" ])
      end
      [ request&.host || "localhost", origins.compact.uniq ]
    end
  end

  rescue_from NotConfigured do
    render json: { error: "Passkeys are not available until the public hostname (APP_HOST) is configured." }, status: :service_unavailable
  end
  allow_unauthenticated_access only: %i[index registration_options create destroy authentication_options callback]
  # Signing in with a passkey comes before the hosted Terms gate.
  allow_without_current_terms only: %i[authentication_options callback]
  before_action :require_user_for_management, only: %i[index registration_options create destroy]
  before_action :forbid_kiosk_access, only: %i[index registration_options create destroy]

  def index
    @passkeys = current_user.passkeys.order(created_at: :desc)
    @household = current_household || current_user.households.first || Household.installation
  end

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

  def destroy
    passkey = current_user.passkeys.find(params[:id])
    passkey.destroy

    redirect_to passkeys_path, notice: "Passkey removed."
  end

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
    rp_id, allowed = self.class.relying_party_settings(request)
    raise NotConfigured if rp_id.blank?

    WebAuthn::RelyingParty.new(
      name: "FamilyPlates",
      id: rp_id,
      allowed_origins: allowed
    )
  end
end
