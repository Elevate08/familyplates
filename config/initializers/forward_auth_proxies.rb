# frozen_string_literal: true

# Forward-auth trusts single proxy addresses only. Say once at startup when an
# entry in FORWARD_AUTH_TRUSTED_PROXIES is ignored (a network range, or not an
# IP address), so an operator can see why forward-auth sign-in stopped.
FamilyPlates.config.log_ignored_forward_auth_proxies(Rails.logger)
