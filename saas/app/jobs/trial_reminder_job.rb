# frozen_string_literal: true

# Scheduled hourly in config/recurring.yml. Emails a household's billing owner
# 72 and 24 hours before its free trial ends: a factual account notice (when
# it ends, that nothing is charged or deleted, where the subscription page
# is), not an offer, so it carries no prices.
#
# Each reminder is due at an instant and is sent by the run in the hour that
# follows; a run that was missed does not catch up later with a stale
# reminder. A trial that is extended has a new end, and its reminders follow
# the new end. NoticeDelivery's unique index means a reminder goes out once,
# however often or concurrently this runs. If sending fails the claim is
# released, so a run still inside the hour tries again; a send that failed
# after the mail server accepted it could, rarely, arrive twice.
class TrialReminderJob < ApplicationJob
  queue_as :default

  KIND = "trial_ending"
  THRESHOLDS = { "72_hours" => 72.hours, "24_hours" => 24.hours }.freeze
  WINDOW = 1.hour

  def perform(now: Time.current)
    return unless FamilyPlates.config.hosted?

    candidates(now).find_each do |household|
      THRESHOLDS.each { |threshold, lead| remind(household, threshold, lead, now) }
    end
  end

  private

  # Households whose trial ends within the longest lead plus the window: by
  # an extension, or FREE_TRIAL_DAYS after creation. The exact due check is
  # done per household.
  def candidates(now)
    horizon = THRESHOLDS.values.max + WINDOW
    trial = Household::Billing::FREE_TRIAL_DAYS.days
    Household.where(suspended_at: nil).where.not(billing_owner_user_id: nil).merge(
      Household.where(trial_extended_until: now..(now + horizon))
        .or(Household.where(trial_extended_until: nil, created_at: (now - trial)..(now - trial + horizon)))
    )
  end

  def remind(household, threshold, lead, now)
    ends_at = household.trial_ends_at
    due = ends_at - lead
    return unless now >= due && now < due + WINDOW
    return unless (owner = eligible_owner(household))

    delivery = NoticeDelivery.claim(household: household, kind: KIND, event_at: ends_at, threshold: threshold)
    return unless delivery

    begin
      TrialReminderMailer.trial_ending(household, owner).deliver_now
      delivery.update!(sent_at: Time.current)
    rescue StandardError => e
      delivery.destroy
      Rails.logger.error("[TrialReminder] #{household.id} #{threshold} not sent: #{e.class}")
    end
  end

  # Still an unpaid trial with nothing pending (trial_banner_state), not
  # suspended or asked to be deleted, and with an owner to write to.
  def eligible_owner(household)
    return unless household.trial_banner_state == :trial
    return if household.suspended?
    return if household.account_deletion_requests.pending.exists?

    owner = household.billing_owner
    owner if owner&.email.present?
  end
end
