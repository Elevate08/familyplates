# frozen_string_literal: true

require "net/http"
require "json"
require "jwt"
require "openssl"

module ExternalAuth
  class Apple < Provider
    AUTH_URL = "https://appleid.apple.com/auth/authorize"
    TOKEN_URL = "https://appleid.apple.com/auth/token"

    def self.enabled?
      FamilyPlates.config.apple_auth_enabled?
    end

    def self.authorization_url(redirect_uri:, state:, nonce:)
      query = {
        client_id: FamilyPlates.config.apple_client_id,
        redirect_uri: redirect_uri,
        response_type: "code id_token",
        response_mode: "form_post",
        scope: "name email",
        state: state,
        nonce: nonce
      }
      "#{AUTH_URL}?#{query.to_query}"
    end

    def self.verify_and_exchange(code: nil, id_token: nil, user_param: nil, redirect_uri: nil, **_options)
      raw_id_token = id_token

      if raw_id_token.blank? && code.present?
        secret = client_secret
        if secret.present?
          uri = URI(TOKEN_URL)
          res = Net::HTTP.post_form(uri, {
            code: code,
            client_id: FamilyPlates.config.apple_client_id,
            client_secret: secret,
            redirect_uri: redirect_uri,
            grant_type: "authorization_code"
          })
          if res.is_a?(Net::HTTPSuccess)
            token_data = JSON.parse(res.body)
            raw_id_token = token_data["id_token"]
          end
        end
      end

      raise "Missing Apple ID token" if raw_id_token.blank?

      payload, _ = JWT.decode(raw_id_token, nil, false)
      sub = payload["sub"]
      email = payload["email"]

      name = nil
      if user_param.present?
        begin
          user_data = user_param.is_a?(String) ? JSON.parse(user_param) : user_param
          name_data = user_data["name"] || {}
          parts = [ name_data["firstName"], name_data["lastName"] ].compact.map(&:presence).compact
          name = parts.join(" ") if parts.any?
        rescue JSON::ParserError
          # Ignore malformed user payload
        end
      end

      {
        provider: "apple",
        uid: sub,
        email: email,
        name: name
      }
    end

    def self.client_secret
      return FamilyPlates.config.apple_client_secret if FamilyPlates.config.apple_client_secret.present?

      key_pem = FamilyPlates.config.apple_private_key
      return nil if key_pem.blank?

      private_key = OpenSSL::PKey::EC.new(key_pem)
      headers = { kid: FamilyPlates.config.apple_key_id }
      claims = {
        iss: FamilyPlates.config.apple_team_id,
        iat: Time.current.to_i,
        exp: (Time.current + 180.days).to_i,
        aud: "https://appleid.apple.com",
        sub: FamilyPlates.config.apple_client_id
      }
      JWT.encode(claims, private_key, "ES256", headers)
    rescue StandardError => e
      Rails.logger.error("Failed to generate Apple client secret: #{e.message}")
      nil
    end
  end
end
