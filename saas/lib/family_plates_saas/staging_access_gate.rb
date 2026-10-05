# frozen_string_literal: true

require "digest"
require "rack/auth/basic"

module FamilyPlatesSaas
  # Staging (dev.familyplates.org) is on the public internet so Stripe can
  # deliver its test-mode webhooks, but nobody else should see the app. Every
  # request needs HTTP Basic credentials except:
  #
  #   POST /pay/webhooks/stripe  Stripe cannot send credentials; Pay checks
  #                              the signature against staging's own secret.
  #   GET  /up                   kamal-proxy's health check.
  #
  # This is the app's own gate. Any proxy or firewall rule put in front of
  # staging must leave those two paths reachable.
  class StagingAccessGate
    OPEN = {
      "/pay/webhooks/stripe" => %w[POST],
      "/up" => %w[GET HEAD]
    }.freeze
    REALM = "FamilyPlates staging"

    def initialize(app, username, password)
      @app = app
      @username = username.to_s
      @password = password.to_s
    end

    def call(env)
      request = Rack::Request.new(env)
      return @app.call(env) if open?(request) || authorized?(env)

      [ 401, { "content-type" => "text/plain", "www-authenticate" => %(Basic realm="#{REALM}"), "cache-control" => "no-store" },
        [ "Staging requires sign-in.\n" ] ]
    end

    private

    def open?(request)
      OPEN.fetch(request.path, []).include?(request.request_method)
    end

    # Never open on blank credentials, even if the boot check were bypassed.
    def authorized?(env)
      return false if @username.empty? || @password.empty?

      auth = Rack::Auth::Basic::Request.new(env)
      return false unless auth.provided? && auth.basic? && auth.credentials

      given_username, given_password = auth.credentials
      same?(given_username, @username) & same?(given_password, @password)
    end

    # Hashed first so the comparison does not reveal the length.
    def same?(given, expected)
      ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(given.to_s), Digest::SHA256.hexdigest(expected))
    end
  end
end
