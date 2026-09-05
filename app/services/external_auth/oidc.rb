# frozen_string_literal: true

require "net/http"
require "json"
require "jwt"

module ExternalAuth
  class Oidc < Provider
    def self.enabled?
      FamilyPlates.config.oidc_enabled?
    end

    def self.authorization_url(redirect_uri:, state:, nonce:)
      auth_endpoint = FamilyPlates.config.oidc_auth_url || discovery_endpoint("authorization_endpoint")
      raise "OIDC authorization endpoint is not configured" if auth_endpoint.blank?

      query = {
        client_id: FamilyPlates.config.oidc_client_id,
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: FamilyPlates.config.oidc_scope,
        state: state,
        nonce: nonce
      }
      "#{auth_endpoint}?#{query.to_query}"
    end

    def self.verify_and_exchange(code: nil, redirect_uri: nil, **_options)
      raise ArgumentError, "Missing authorization code" if code.blank?

      token_endpoint = FamilyPlates.config.oidc_token_endpoint || discovery_endpoint("token_endpoint")
      raise "OIDC token endpoint is not configured" if token_endpoint.blank?

      uri = URI(token_endpoint)
      req = Net::HTTP::Post.new(uri)
      req.set_form_data({
        code: code,
        client_id: FamilyPlates.config.oidc_client_id,
        client_secret: FamilyPlates.config.oidc_client_secret,
        redirect_uri: redirect_uri,
        grant_type: "authorization_code"
      })
      req.basic_auth(FamilyPlates.config.oidc_client_id, FamilyPlates.config.oidc_client_secret)

      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
      raise "OIDC token exchange failed: #{res.code} #{res.body}" unless res.is_a?(Net::HTTPSuccess)

      token_data = JSON.parse(res.body)
      access_token = token_data["access_token"]
      id_token = token_data["id_token"]

      userinfo = fetch_userinfo(access_token, id_token)
      {
        provider: "oidc",
        uid: userinfo["sub"] || userinfo["id"] || userinfo["preferred_username"],
        email: userinfo["email"],
        name: userinfo["name"] || userinfo["preferred_username"]
      }
    end

    def self.fetch_userinfo(access_token, id_token = nil)
      userinfo_endpoint = FamilyPlates.config.oidc_userinfo_endpoint || discovery_endpoint("userinfo_endpoint")
      if userinfo_endpoint.present? && access_token.present?
        uri = URI(userinfo_endpoint)
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{access_token}"
        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
        return JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
      end

      if id_token.present?
        payload, _ = JWT.decode(id_token, nil, false)
        return payload
      end

      raise "Could not fetch OIDC user information"
    end

    def self.discovery_endpoint(key)
      endpoints = discovery_endpoints
      endpoints[key]
    end

    def self.discovery_endpoints
      return @discovery_endpoints if defined?(@discovery_endpoints) && @discovery_endpoints.present?

      issuer = FamilyPlates.config.oidc_issuer
      return {} if issuer.blank?

      discovery_url = "#{issuer.chomp('/')}/.well-known/openid-configuration"
      uri = URI(discovery_url)
      res = Net::HTTP.get_response(uri)
      if res.is_a?(Net::HTTPSuccess)
        @discovery_endpoints = JSON.parse(res.body)
      else
        {}
      end
    rescue StandardError => e
      Rails.logger.warn("OIDC discovery failed for #{issuer}: #{e.message}")
      {}
    end

    def self.reset_discovery!
      @discovery_endpoints = nil
    end
  end
end
