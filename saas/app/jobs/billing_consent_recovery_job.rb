# frozen_string_literal: true

# Scheduled in config/recurring.yml. Sends acknowledgments that are due,
# including ones whose job was never queued, and settles Checkout attempts
# whose outcome was lost. See BillingConsent.recover!.
class BillingConsentRecoveryJob < ApplicationJob
  queue_as :default

  def perform
    BillingConsent.recover!
  end
end
