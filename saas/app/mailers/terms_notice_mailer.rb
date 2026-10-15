# frozen_string_literal: true

# Tells someone who agreed to an earlier version of the hosted Terms of
# Service that a new version is coming, when it applies to them, and that
# they will be asked to accept it. See TermsNotice.
class TermsNoticeMailer < ApplicationMailer
  def changed_terms(notice, user)
    @notice = notice
    @terms_url = terms_url
    @acceptance_url = terms_acceptance_url
    @subscription_url = subscription_url
    @support_email = BillingOffer::SUPPORT_EMAIL

    mail to: user.email, subject: "The FamilyPlates Terms of Service are changing"
  end
end
