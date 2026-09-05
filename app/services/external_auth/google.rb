# frozen_string_literal: true

require "net/http"
require "json"
require "jwt"

module ExternalAuth
  class Google < Provider
    AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
    TOKEN_URL = "https://oauth2.googleapis.com/token"
    USERINFO_URL = "https://openidconnect.googleapis.com/v1/userinfo"

    def self.enabled?
      FamilyPlates.config.google_auth_enabled?
    end

    def self.authorization_url(redirect_uri:, state:, nonce:)
      query = {
        client_id: FamilyPlates.config.google_client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: "openid email profile",
        state: state,
        nonce: nonce,
        prompt: "select_account"
      }
      "#{AUTH_URL}?#{query.to_query}"
    end

    def self.verify_and_exchange(code: nil, redirect_uri: nil, **_options)
      raise ArgumentError, "Missing authorization code" if code.blank?

      uri = URI(TOKEN_URL)
      res = Net::HTTP.post_form(uri, {
        code: code,
        client_id: FamilyPlates.config.google_client_id,
        client_secret: FamilyPlates.config.google_client_secret,
        redirect_uri: redirect_uri,
        grant_type: "authorization_code"
      })

      raise "Google token exchange failed: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)

      token_data = JSON.parse(res.body)
      access_token = token_data["access_token"]
      id_token = token_data["id_token"]

      userinfo = fetch_userinfo(access_token, id_token)
      {
        provider: "google",
        uid: userinfo["sub"],
        email: userinfo["email"],
        name: userinfo["name"]
      }
    end

    def self.fetch_userinfo(access_token, id_token = nil)
      if access_token.present?
        uri = URI(USERINFO_URL)
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{access_token}"
        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
        return JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
      end

      if id_token.present?
        payload, _ = JWT.decode(id_token, nil, false)
        return payload
      end

      raise "Could not fetch Google user information"
    end
  end
end
