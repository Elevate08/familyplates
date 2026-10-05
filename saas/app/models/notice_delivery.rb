# frozen_string_literal: true

# A reminder sent, or being sent, about one event. See TrialReminderJob.
class NoticeDelivery < ApplicationRecord
  attribute :id, default: -> { SecureRandom.uuid }

  # Claims this reminder, or returns nil if it is already claimed. The unique
  # index decides, so two runs at once cannot both send it.
  def self.claim(household:, kind:, event_at:, threshold:)
    create!(household_id: household.id, kind: kind, event_at: event_at, threshold: threshold)
  rescue ActiveRecord::RecordNotUnique
    nil
  end
end
