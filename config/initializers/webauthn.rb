# frozen_string_literal: true

WebAuthn.configure do |config|
  # Relying Party name displayed in browser passkey prompts
  config.rp_name = "FamilyPlates"

  # Defaults; controllers pass dynamic request.origin and request.host
  # to support appliance-mode LAN IPs, mDNS (.local), and hosted domains.
  origin = ENV.fetch("APP_ORIGIN", "http://localhost:3000")
  config.allowed_origins = [origin, "http://localhost:3000", "http://127.0.0.1:3000"]
  config.rp_id = ENV.fetch("APP_RP_ID", "localhost")
end
