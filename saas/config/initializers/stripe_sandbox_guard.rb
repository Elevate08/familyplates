# frozen_string_literal: true

# Refuses to boot the test environment with a live Stripe key. See
# FamilyPlatesSaas::StripeSandbox.
Rails.application.config.after_initialize do
  FamilyPlatesSaas::StripeSandbox.verify!
end
