# frozen_string_literal: true

module LoginThrottling
  extend ActiveSupport::Concern

  MAX_ATTEMPTS = 10
  WINDOW = 3.minutes
  SCOPE = "login_attempts".freeze

  class_methods do
    def throttle_login_attempts(only:)
      rate_limit to: MAX_ATTEMPTS, within: WINDOW, name: "login_by_ip", scope: SCOPE,
                 store: LoginThrottling.store,
                 by: -> { "ip:#{request.remote_ip}" },
                 with: -> { login_attempts_throttled!(:ip) },
                 only: only

      rate_limit to: MAX_ATTEMPTS, within: WINDOW, name: "login_by_email", scope: SCOPE,
                 store: LoginThrottling.store,
                 by: -> { "email:#{throttled_email}" },
                 with: -> { login_attempts_throttled!(:email) },
                 only: only, if: -> { throttled_email.present? }
    end
  end

  def self.store
    Rails.application.config.pin_attempt_store
  end

  private

  # submit_verify carries no email param; its address lives in the session.
  def throttled_email
    (params[:email].presence || session[:pending_auth_email]).to_s.strip.downcase
  end

  def login_attempts_throttled!(limit)
    Rails.logger.warn("[auth] login_throttled limit=#{limit} ip=#{request.remote_ip} path=#{request.path}")
    redirect_to login_throttled_path, alert: "Too many sign-in attempts. Please wait a few minutes and try again."
  end

  # Where a throttled attempt is sent: the sign-in form it came from.
  def login_throttled_path
    new_session_path
  end
end
