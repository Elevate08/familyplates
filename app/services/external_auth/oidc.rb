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

    def self.verify_and_exchange(code: nil, redirect_uri: nil, nonce: nil, **_options)
      raise ArgumentError, "Missing authorization code" if code.blank?

      token_endpoint = FamilyPlates.config.oidc_token_url || discovery_endpoint("token_endpoint")
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

      res = http_request(uri, req)
      raise "OIDC token exchange failed: #{res.code}" unless res.is_a?(Net::HTTPSuccess)

      token_data = JSON.parse(res.body)
      access_token = token_data["access_token"]
      id_token = token_data["id_token"]

      userinfo = fetch_userinfo(access_token, id_token, nonce: nonce)
      {
        provider: "oidc",
        uid: userinfo["sub"] || userinfo["id"] || userinfo["preferred_username"],
        email: userinfo["email"],
        email_verified: email_verified_claim(userinfo),
        name: userinfo["name"] || userinfo["preferred_username"]
      }
    end

    # The id_token is always verified (signature, issuer, audience, expiry,
    # nonce); userinfo only adds to it. See Provider.merge_userinfo.
    def self.fetch_userinfo(access_token, id_token = nil, nonce: nil)
      raise "OIDC provider returned no id_token" if id_token.blank?

      claims = verify_id_token(
        id_token,
        jwks: jwks_loader,
        issuer: expected_issuers,
        audience: FamilyPlates.config.oidc_client_id,
        nonce: nonce
      )
      merge_userinfo(claims, (request_userinfo(access_token) if access_token.present?))
    end

    # Some self-hosted identity providers leave email_verified out. An
    # appliance's provider is configured by its owner, so a missing claim is
    # trusted there; an explicit false never is, and the hosted service
    # requires the claim.
    def self.email_verified_claim(info)
      if info.key?("email_verified")
        value = info["email_verified"]
        value == true || value.to_s == "true"
      elsif !FamilyPlates.config.hosted?
        true
      end
    end

    def self.request_userinfo(access_token)
      userinfo_endpoint = FamilyPlates.config.oidc_userinfo_url || discovery_endpoint("userinfo_endpoint")
      return if userinfo_endpoint.blank?

      uri = URI(userinfo_endpoint)
      req = Net::HTTP::Get.new(uri)
      req["Authorization"] = "Bearer #{access_token}"
      res = http_request(uri, req)
      JSON.parse(res.body) if res.is_a?(Net::HTTPSuccess)
    end
    private_class_method :request_userinfo

    # The issuer the provider publishes in its discovery document, and the one
    # configured, each with and without a trailing slash: Authentik, for one,
    # publishes a trailing slash that operators often leave off.
    def self.expected_issuers
      [ discovery_endpoint("issuer"), FamilyPlates.config.oidc_issuer ].compact_blank
        .flat_map { |issuer| [ issuer.chomp("/"), "#{issuer.chomp('/')}/" ] }.uniq
    end

    def self.jwks
      jwks_uri = FamilyPlates.config.oidc_jwks_url.presence || discovery_endpoint("jwks_uri")
      raise "OIDC JWKS endpoint is not available" if jwks_uri.blank?

      uri = URI(jwks_uri)
      res = http_request(uri, Net::HTTP::Get.new(uri))
      raise "OIDC JWKS fetch failed: #{res.code}" unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(res.body)
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
      res = http_request(uri, Net::HTTP::Get.new(uri))
      if res.is_a?(Net::HTTPSuccess)
        @discovery_endpoints = JSON.parse(res.body)
      else
        {}
      end
    rescue StandardError => e
      Rails.logger.warn("OIDC discovery failed (#{e.class})")
      {}
    end

    def self.reset_discovery!
      @discovery_endpoints = nil
    end

    def self.http_request(uri, req)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(req) }
    end
    private_class_method :http_request
  end
end
