# frozen_string_literal: true

module ExternalAuth
  class Provider
    def self.enabled?
      false
    end

    def self.authorization_url(redirect_uri:, state:, nonce:)
      raise NotImplementedError
    end

    def self.verify_and_exchange(code: nil, id_token: nil, user_param: nil, redirect_uri: nil)
      raise NotImplementedError
    end
  end
end
