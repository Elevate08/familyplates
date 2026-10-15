# frozen_string_literal: true

# Tells a household's billing owner when its free trial ends. An account
# notice, not an offer: no prices or plans. See TrialReminderJob.
class TrialReminderMailer < ApplicationMailer
  def trial_ending(household, owner)
    @household = household
    ends_at = household.trial_ends_at
    @ends_at_utc = ends_at.utc
    @ends_at_local = ends_at.in_time_zone(household.time_zone_object).strftime("%B %-d, %Y at %-l:%M %p %Z")
    @subscription_url = subscription_url
    @support_email = BillingOffer::SUPPORT_EMAIL

    mail to: owner.email, subject: "Your FamilyPlates free trial ends #{ends_at.in_time_zone(household.time_zone_object).strftime("%B %-d")}"
  end
end
