# frozen_string_literal: true

module ExternalAuth
  class Provider
    def self.enabled?
      false
    end

    def self.authorization_url(redirect_uri:, state:, nonce:)
      raise NotImplementedError
    end

    def self.verify_and_exchange(code: nil, redirect_uri: nil, nonce: nil)
      raise NotImplementedError
    end

    JWKS_TTL = 1.hour

    # Verifies an id_token received from the provider's token endpoint: RS256
    # signature against the provider JWKS, issuer (one or a list), audience,
    # expiry and nonce. jwks is the key set, or a loader such as jwks_loader.
    def self.verify_id_token(token, jwks:, issuer:, audience:, nonce:)
      raise JWT::DecodeError, "Missing nonce" if nonce.blank? || audience.blank?

      payload, _header = JWT.decode(
        token,
        nil,
        true,
        algorithms: [ "RS256" ],
        jwks: jwks.respond_to?(:call) ? jwks : ->(_options) { jwks },
        iss: issuer,
        verify_iss: true,
        aud: audience,
        verify_aud: true,
        verify_expiration: true
      )

      unless ActiveSupport::SecurityUtils.secure_compare(payload["nonce"].to_s, nonce.to_s)
        raise JWT::DecodeError, "Nonce mismatch"
      end

      payload
    end

    # The provider's signing keys, kept for JWKS_TTL so sign-in does not wait
    # on a fetch every time, and fetched again at once when a token names a
    # key the cache lacks (the provider rotated its keys). Per provider class.
    def self.jwks_loader
      lambda do |options|
        if @jwks_cache.nil? || options[:kid_not_found] || @jwks_fetched_at < JWKS_TTL.ago
          @jwks_cache = jwks
          @jwks_fetched_at = Time.current
        end
        @jwks_cache
      end
    end

    def self.reset_jwks_cache!
      @jwks_cache = @jwks_fetched_at = nil
    end

    # The verified id_token is the identity. Userinfo, when the provider
    # answers, only adds fields, only for the same subject, and never
    # overrides a signed claim.
    def self.merge_userinfo(claims, userinfo)
      return claims if userinfo.nil?
      raise "Userinfo subject does not match the id_token" unless userinfo["sub"].to_s == claims["sub"].to_s

      userinfo.merge(claims)
    end
  end
end
