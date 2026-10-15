# frozen_string_literal: true

require "net/smtp"

# Notice, to someone who agreed to an earlier version of the hosted Terms of
# Service, that a new version is coming and when it will apply to them. One
# per person per version, enforced by the database, so scheduling and
# delivery can run any number of times.
#
# The new version applies to them no earlier than the date the email states
# (claim time + NOTICE_LEAD_TIME) and no earlier than NOTICE_LEAD_TIME after
# the email was submitted for delivery. Until a notice is recorded as
# submitted, the change is held for them: no proof of notice, no enforcement.
#
# state:
# - "queued": due to be sent.
# - "sending": claimed by a worker that has not finished.
# - "submitted": handed to the mail server; submitted_at is the proof.
# - "uncertain": the send may or may not have gone out. Held for an operator
#   (#resolve_uncertain!), never resent automatically.
# - "failed": could not be sent after MAX_ATTEMPTS. Held for an operator.
# - "skipped": no longer needed - the person accepted the version, it was
#   superseded by a later one, or the person was deleted.
#
# Only identifiers, versions and timestamps are kept; the address is read
# from the user at send time.
class TermsNotice < ApplicationRecord
  STATES = %w[queued sending submitted uncertain failed skipped].freeze
  MAX_ATTEMPTS = 5
  CLAIM_TIMEOUT = 15.minutes


  attribute :id, default: -> { SecureRandom.uuid }

  belongs_to :user, optional: true

  validates :user_id, :terms_version, presence: true
  validates :state, inclusion: { in: STATES }

  # Whether `version` may now be required of `user`: a notice was submitted
  # and its lead time has passed.
  def self.enforceable?(user, version, now: Time.current)
    notice = find_by(user_id: user.id, terms_version: version, state: "submitted")
    notice.present? && notice.enforcement_at(user) <= now
  end

  # When the current version starts being required of `user`, if a notice
  # has been submitted. For the in-app notice.
  def self.enforcement_at_for(user, version = TermsAssent.current_version)
    find_by(user_id: user.id, terms_version: version, state: "submitted")&.enforcement_at(user)
  end

  # Queues a notice of the current version for everyone who agreed to an
  # earlier one. Idempotent: the unique index on (user_id, terms_version)
  # means a person gets one notice per version however often this runs.
  def self.schedule!
    version = TermsAssent.current_version
    noticed = where(terms_version: version).select(:user_id)
    queued = 0
    # Two where.not calls: NOT IN with a NULL in the list matches nothing.
    User.where.not(terms_version: nil).where.not(terms_version: [ "", version ]).where.not(id: noticed).find_each do |user|
      create!(user_id: user.id, terms_version: version, previous_terms_version: user.terms_version)
      queued += 1
    rescue ActiveRecord::RecordNotUnique
      next
    end
    queued
  end

  # The recurring TermsNoticeJob: queues new notices, holds sends whose
  # worker vanished, and sends every queued notice for the current version.
  def self.recover!(now: Time.current)
    summary = Hash.new(0)
    summary[:queued] = schedule!
    where(state: "queued").where.not(terms_version: TermsAssent.current_version)
      .update_all(state: "skipped", last_error: "Superseded by a later Terms version", updated_at: now)
    where(state: "sending", claimed_at: ...(now - CLAIM_TIMEOUT)).find_each do |notice|
      notice.mark_uncertain!("Claimed at #{notice.claimed_at.utc.iso8601} and never marked submitted; the worker was lost")
      summary[:uncertain] += 1
    end
    where(state: "queued", terms_version: TermsAssent.current_version).find_each do |notice|
      summary[:submitted] += 1 if notice.deliver!(now: now)
    rescue StandardError => e
      Rails.error.report(e, handled: true, context: { terms_notice_id: notice.id })
    end
    summary[:awaiting_operator] = where(state: %w[uncertain failed]).count

    if summary.values.any?(&:positive?)
      Rails.logger.warn("[TermsNotice] recovery: #{summary.map { |key, count| "#{key}=#{count}" }.join(" ")}")
    end
    summary
  end

  # The later of the date the email stated and the end of the notice period
  # counted from submission. Recomputed on read, so joining a household in
  # another zone can only move it later.
  def enforcement_at(recipient = User.find_by(id: user_id))
    return unless submitted_at
    return [ stated_enforcement_at, submitted_at + TermsAssent::NOTICE_LEAD_TIME ].compact.max if recipient.nil?

    [ stated_enforcement_at, TermsAssent.notice_period_end(recipient, submitted_at) ].compact.max
  end

  # Sends this notice, never twice. Returns whether this call submitted it.
  def deliver!(now: Time.current)
    return false unless state == "queued"

    recipient = User.find_by(id: user_id)
    if recipient.nil? || terms_version != TermsAssent.current_version || recipient.terms_version == terms_version
      self.class.where(id: id, state: "queued").update_all(state: "skipped", updated_at: now)
      return false
    end

    stated = TermsAssent.notice_period_end(recipient, now)
    claimed = self.class.where(id: id, state: "queued").update_all(
      state: "sending", claimed_at: now, stated_enforcement_at: stated, attempts: attempts + 1, updated_at: now
    )
    return false unless claimed == 1

    reload
    begin
      # Rendered before anything is handed to the mail server.
      message = TermsNoticeMailer.changed_terms(self, recipient)
      message.message
    rescue StandardError => e
      retry_or_fail!(e)
      return false
    end

    begin
      message.deliver_now
    rescue *ApplicationMailer::NOT_SENT_ERRORS => e
      retry_or_fail!(e)
      return false
    rescue StandardError => e
      mark_uncertain!(e)
      return false
    end

    self.class.where(id: id, state: "sending").update_all(state: "submitted", submitted_at: Time.current, last_error: nil,
      updated_at: Time.current)
    true
  end

  def mark_uncertain!(error)
    message = (error.is_a?(Exception) ? "#{error.class}: #{error.message}" : error.to_s).truncate(255)
    marked = self.class.where(id: id, state: "sending").update_all(state: "uncertain", last_error: message, updated_at: Time.current)
    return if marked.zero?

    Rails.logger.error("[TermsNotice] #{id} may or may not have been delivered; not resending. " \
      "Check the mail provider, then resolve_uncertain!: #{message}")
  end

  # For an operator who has checked the mail provider's log:
  #   TermsNotice.find(id).resolve_uncertain!(delivered: true, submitted_at: <time in the provider's log>)
  # records it as submitted at the time the provider recorded accepting it;
  #   TermsNotice.find(id).resolve_uncertain!(delivered: true)
  # when the log shows it went out but not exactly when, records it as
  # submitted now - the latest it can have been - never at the claim time,
  # which can be minutes before the mail server actually took it;
  #   TermsNotice.find(id).resolve_uncertain!(delivered: false)
  # queues it again, with a new stated date.
  def resolve_uncertain!(delivered:, submitted_at: nil)
    raise ArgumentError, "Terms notice #{id} is not uncertain" unless reload.state == "uncertain"

    now = Time.current
    if delivered
      proven = submitted_at || now
      if proven < claimed_at || proven > now
        raise ArgumentError, "Terms notice #{id} cannot have been submitted at #{proven.utc.iso8601}: " \
          "it was claimed at #{claimed_at.utc.iso8601} and it is now #{now.utc.iso8601}"
      end
      update_columns(state: "submitted", submitted_at: proven, last_error: nil, updated_at: now)
    elsif submitted_at
      raise ArgumentError, "a submission time is only recorded for a delivered notice"
    else
      update_columns(state: "queued", claimed_at: nil, stated_enforcement_at: nil, attempts: 0, updated_at: now)
    end
  end

  private

  def retry_or_fail!(error)
    message = "#{error.class}: #{error.message}".truncate(255)
    next_state = attempts >= MAX_ATTEMPTS ? "failed" : "queued"
    self.class.where(id: id, state: "sending").update_all(state: next_state, claimed_at: nil, stated_enforcement_at: nil,
      last_error: message, updated_at: Time.current)
    Rails.logger.warn("[TermsNotice] #{id} not sent (#{next_state}): #{message}")
  end
end
