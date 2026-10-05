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

    # Verifies an id_token received from the provider's token endpoint: RS256
    # signature against the provider JWKS, issuer, audience, expiry and nonce.
    def self.verify_id_token(token, jwks:, issuer:, audience:, nonce:)
      raise JWT::DecodeError, "Missing nonce" if nonce.blank? || audience.blank?

      payload, _header = JWT.decode(
        token,
        nil,
        true,
        algorithms: [ "RS256" ],
        jwks: ->(_options) { jwks },
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
