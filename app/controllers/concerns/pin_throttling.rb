module PinThrottling
  extend ActiveSupport::Concern

  MAX_ATTEMPTS = 10
  WINDOW = 3.minutes

  # Both PIN entry paths draw on one budget. Scoping per controller would let an
  # attacker take MAX_ATTEMPTS at /set_profile and MAX_ATTEMPTS more at
  # /family_members/:id/switch against the same profile.
  SCOPE = "pin_attempts".freeze

  class_methods do
    # Per-IP stops one host trying every profile; per-profile stops a distributed attack on one organizer.
    # A profile with no PIN is not counted, so 1-tap switching is unaffected.
    def throttle_pin_attempts(only:)
      rate_limit to: MAX_ATTEMPTS, within: WINDOW, name: "by_ip", scope: SCOPE,
                 store: PinThrottling.store,
                 by: -> { "ip:#{request.remote_ip}" },
                 with: -> { pin_attempts_throttled!(:ip) },
                 only: only, if: -> { pin_protected_target? }

      rate_limit to: MAX_ATTEMPTS, within: WINDOW, name: "by_profile", scope: SCOPE,
                 store: PinThrottling.store,
                 by: -> { "profile:#{throttled_profile_id}" },
                 with: -> { pin_attempts_throttled!(:profile) },
                 only: only, if: -> { pin_protected_target? }
    end
  end

  def self.store
    Rails.application.config.pin_attempt_store
  end

  private

  def throttled_profile_id
    params[:id] || current_family_member&.id
  end

  # The same places a PIN can be checked. Current.household alone misses a
  # profile the signed-in user belongs to in another household, and both rate
  # limits are skipped when this returns false.
  def pin_protected_target?
    pin_target_member&.requires_pin? || false
  end

  def pin_target_member
    target_id = throttled_profile_id
    return if target_id.blank?

    Current.household&.family_members&.find_by(id: target_id) ||
      Current.user&.family_members&.find_by(id: target_id) ||
      (Household.installation&.family_members&.find_by(id: target_id) unless FamilyPlates.config.hosted?)
  end

  # Runs as a before_action, so it cannot know whether the submitted PIN was
  # correct — which is the point. A throttled attempt looks identical either way.
  def pin_attempts_throttled!(limit)
    target_id = throttled_profile_id
    Rails.logger.warn("[auth] pin_throttled limit=#{limit} profile_id=#{target_id} ip=#{request.remote_ip} path=#{request.path}")
    redirect_target = (request.path == preferences_path ? edit_preferences_path : select_profile_path)
    redirect_to redirect_target, alert: "Too many attempts. Please wait a few minutes and try again."
  end

  def log_pin_failure(member)
    Rails.logger.warn("[auth] pin_failure profile_id=#{member.id} ip=#{request.remote_ip} path=#{request.path}")
  end
end
