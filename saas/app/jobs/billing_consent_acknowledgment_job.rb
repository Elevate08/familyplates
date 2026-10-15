# frozen_string_literal: true

# Emails the billing owner a copy of the renewal terms they agreed to, once
# their subscription is confirmed active. Not retried by Active Job: the
# consent row records when the next attempt is due, and
# BillingConsentRecoveryJob makes it. See BillingConsent#deliver_acknowledgment
# for why a send that may have gone out is never repeated.
class BillingConsentAcknowledgmentJob < ApplicationJob
  queue_as :default

  def perform(billing_consent_id)
    BillingConsent.find_by(id: billing_consent_id)&.deliver_acknowledgment
  end
end
