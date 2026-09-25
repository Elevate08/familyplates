# frozen_string_literal: true

class ExternalAuthController < ApplicationController
  allow_unauthenticated_access only: %i[passthru callback]
  skip_before_action :verify_authenticity_token, only: :callback

  def passthru
    provider_name = params[:provider].to_s.downcase
    provider = ExternalAuth.provider_for(provider_name)

    unless provider&.enabled?
      target = current_user ? edit_preferences_path : new_session_path
      redirect_to target, alert: "#{provider_name.titleize} authentication is not enabled." and return
    end

    state = SecureRandom.hex(24)
    nonce = SecureRandom.hex(24)

    session[:oauth_state] = state
    session[:oauth_nonce] = nonce
    session[:oauth_provider] = provider_name
    session[:oauth_connecting] = current_user.present?

    callback_url = auth_callback_url(provider: provider_name)
    auth_url = provider.authorization_url(redirect_uri: callback_url, state: state, nonce: nonce)

    redirect_to auth_url, allow_other_host: true
  end

  def callback
    provider_name = params[:provider].to_s.downcase
    stored_provider = session.delete(:oauth_provider)
    stored_state = session.delete(:oauth_state)
    _stored_nonce = session.delete(:oauth_nonce)
    connecting = session.delete(:oauth_connecting)

    target_fallback = (connecting && current_user) ? edit_preferences_path : new_session_path

    if params[:error].present?
      redirect_to target_fallback, alert: "Authentication failed: #{params[:error_description] || params[:error]}." and return
    end

    if stored_state.blank? || params[:state] != stored_state || provider_name != stored_provider
      redirect_to target_fallback, alert: "Authentication failed: invalid state." and return
    end

    provider = ExternalAuth.provider_for(provider_name)
    unless provider&.enabled?
      redirect_to target_fallback, alert: "#{provider_name.titleize} authentication is not enabled." and return
    end

    callback_url = auth_callback_url(provider: provider_name)
    auth_data = provider.verify_and_exchange(
      code: params[:code],
      id_token: params[:id_token],
      user_param: params[:user],
      redirect_uri: callback_url
    )

    uid = auth_data[:uid]
    email = auth_data[:email]

    if uid.blank?
      redirect_to target_fallback, alert: "Authentication failed: no unique identifier returned by #{provider_name.titleize}." and return
    end

    if connecting && current_user
      existing_identity = Identity.find_by(provider: provider_name, uid: uid)
      if existing_identity
        if existing_identity.user_id == current_user.id
          redirect_to edit_preferences_path, notice: "#{provider_name.titleize} is already connected to your account."
        else
          redirect_to edit_preferences_path, alert: "This #{provider_name.titleize} account is already linked to another user."
        end
        return
      end

      current_user.identities.create!(provider: provider_name, uid: uid)
      redirect_to edit_preferences_path, notice: "Successfully connected #{provider_name.titleize} to your account!"
    else
      user = User.find_or_create_from_identity(
        provider: provider_name,
        uid: uid,
        email: email,
        name: auth_data[:name]
      )

      start_new_session_for_user(user)
      redirect_to after_authentication_url, notice: "Signed in successfully with #{provider_name.titleize}."
    end
  rescue StandardError => e
    Rails.logger.error("External authentication error (#{provider_name}): #{e.message}")
    target = (connecting && current_user) ? edit_preferences_path : new_session_path
    redirect_to target, alert: "Authentication error: #{e.message}"
  end

  def destroy_identity
    identity = current_user.identities.find(params[:id])

    if current_user.can_disconnect_identity?(identity)
      provider_name = identity.display_provider
      identity.destroy
      redirect_to edit_preferences_path, notice: "Disconnected #{provider_name} account."
    else
      redirect_to edit_preferences_path, alert: "Cannot disconnect this sign-in method. You must keep at least one way to sign in (password, passkey, or another connected account)."
    end
  end
end
