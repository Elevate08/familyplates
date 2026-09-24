# frozen_string_literal: true

# Refuses to boot the test environment with a live Stripe key. See
# FamilyPlates::StripeSandbox.
Rails.application.config.after_initialize do
  FamilyPlates::StripeSandbox.verify!
end
