module PinThrottling
  extend ActiveSupport::Concern

  MAX_ATTEMPTS = 10
  WINDOW = 3.minutes

  # Both PIN entry paths draw on one budget. Scoping per controller would let an
  # attacker take MAX_ATTEMPTS at /set_profile and MAX_ATTEMPTS more at
  # /family_members/:id/switch against the same profile.
  SCOPE = "pin_attempts".freeze

  class_methods do
    # Two limits, because they stop different attacks: the per-IP one stops a
    # single host working through every profile, the per-profile one stops a
    # distributed attack on one organizer. A profile with no PIN is not a
    # credential check at all and is never counted, so ordinary 1-tap member
    # switching is unaffected.
    def throttle_pin_attempts(only:)
      rate_limit to: MAX_ATTEMPTS, within: WINDOW, name: "by_ip", scope: SCOPE,
                 store: PinThrottling.store,
                 by: -> { "ip:#{request.remote_ip}" },
                 with: -> { pin_attempts_throttled!(:ip) },
                 only: only, if: -> { pin_protected_target? }

      rate_limit to: MAX_ATTEMPTS, within: WINDOW, name: "by_profile", scope: SCOPE,
                 store: PinThrottling.store,
                 by: -> { "profile:#{params[:id]}" },
                 with: -> { pin_attempts_throttled!(:profile) },
                 only: only, if: -> { pin_protected_target? }
    end
  end

  def self.store
    Rails.application.config.pin_attempt_store
  end

  private

  def pin_protected_target?
    FamilyMember.find_by(id: params[:id])&.requires_pin? || false
  end

  # Runs as a before_action, so it cannot know whether the submitted PIN was
  # correct — which is the point. A throttled attempt looks identical either way.
  def pin_attempts_throttled!(limit)
    Rails.logger.warn("[auth] pin_throttled limit=#{limit} profile_id=#{params[:id]} ip=#{request.remote_ip} path=#{request.path}")
    redirect_to select_profile_path, alert: "Too many attempts. Please wait a few minutes and try again."
  end

  def log_pin_failure(member)
    Rails.logger.warn("[auth] pin_failure profile_id=#{member.id} ip=#{request.remote_ip} path=#{request.path}")
  end
end
