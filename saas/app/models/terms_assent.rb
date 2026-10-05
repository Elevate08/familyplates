# frozen_string_literal: true

# Who has agreed to the hosted Terms of Service, and who must agree before
# using a household. A person agrees for themselves, by ticking an unticked
# box: when they sign up, join a household, claim a profile, or accept a new
# version. Signing in, including with Google, is never agreement. Profiles
# without a sign-in of their own are covered by the owner and agree to
# nothing here.
#
# The user row holds the version they last agreed to (the gate reads it);
# TermsAcceptance keeps every agreement as retained evidence.
#
# A changed version is enforced on someone who agreed to an earlier one only
# once a notice to them was submitted for delivery at least NOTICE_LEAD_TIME
# earlier (TermsNotice). Without that proof the change is held for them and
# the in-app notice asks them to accept it. Someone who never agreed to any
# version must agree before using a household.
module TermsAssent
  NOTICE_LEAD_TIME = 30.days
  # first_use: a signed-in person who had never agreed, before using a household.
  CONTEXTS = %w[signup join claim first_use reacceptance].freeze
  ALERT = "Please confirm you are 18 or older, live in the United States, and agree to the Terms of Service."
  VERSION_CHANGED_ALERT = "The Terms of Service changed while this page was open. Please review them and try again."
  # A shared kitchen display is signed in as someone, but whoever is standing
  # at it is not necessarily them: no one agrees to the Terms, signs up,
  # joins a household or claims a profile from one.
  KIOSK_ALERT = "Terms of Service can only be accepted from your own device, not a shared kitchen display."

  # Every reader of the current version goes through here, so a test can
  # publish a new version without editing Legal.
  def self.current_version
    Legal::TERMS_VERSION
  end

  # The end of the notice period for a notice to `user` submitted at `from`:
  # NOTICE_LEAD_TIME later at the same wall-clock time, in UTC and in every
  # household zone the person belongs to, whichever is latest. Across a
  # daylight-saving change, 30 local days can be an hour longer than 720
  # hours; the period never ends before 30 days have passed where they live.
  def self.notice_period_end(user, from)
    zones = [ "UTC" ] + Household.joins(:family_members).where(family_members: { user_id: user.id }).distinct.pluck(:time_zone)
    zones.compact_blank.uniq.filter_map { |name| ActiveSupport::TimeZone[name] }
      .map { |zone| from.in_time_zone(zone) + NOTICE_LEAD_TIME }.max.utc
  end

  def self.current?(user)
    user.present? && user.terms_version.present? && user.terms_version == current_version
  end

  # The user has agreed to an earlier version and not yet to this one.
  def self.pending_change?(user)
    user.present? && user.terms_version.present? && !current?(user)
  end

  def self.acceptance_required?(user, now: Time.current)
    return false if user.nil? || current?(user)
    return true if user.terms_version.blank?

    TermsNotice.enforceable?(user, current_version, now: now)
  end

  # Records that the user agreed to `version` just now. Refuses any version
  # but the current one: a person cannot agree to Terms they were not shown,
  # and an older version would leave them needing to accept again anyway.
  def self.accept!(user, version:, context:, household: nil, at: Time.current)
    raise ArgumentError, "unknown Terms acceptance context #{context.inspect}" unless CONTEXTS.include?(context)
    return false unless version.present? && version == current_version

    User.transaction do
      user.update!(terms_accepted_at: at, terms_version: version)
      TermsAcceptance.create!(user_id: user.id, household_id: household&.id, terms_version: version,
        accepted_at: at, context: context)
    end
    true
  end
end
