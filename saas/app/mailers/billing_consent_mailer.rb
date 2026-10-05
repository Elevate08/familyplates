# frozen_string_literal: true

# The retainable acknowledgment of a paid subscription: the terms the billing
# owner agreed to, word for word, what Stripe actually charged, how to
# request a refund and how to cancel.
class BillingConsentMailer < ApplicationMailer
  def acknowledgment(consent)
    @consent = consent
    @subscription_url = subscription_url
    @terms_url = terms_url
    @support_email = BillingOffer::SUPPORT_EMAIL

    mail to: consent.user.email, subject: "Your FamilyPlates #{consent.plan_name} subscription: renewal terms and how to cancel"
  end
end
