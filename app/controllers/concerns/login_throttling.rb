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
                 by: -> { "email:#{params[:email].to_s.strip.downcase}" },
                 with: -> { login_attempts_throttled!(:email) },
                 only: only, if: -> { params[:email].present? }
    end
  end

  def self.store
    Rails.application.config.pin_attempt_store
  end

  private

  def login_attempts_throttled!(limit)
    Rails.logger.warn("[auth] login_throttled limit=#{limit} ip=#{request.remote_ip} email=#{params[:email].to_s.strip.downcase}")
    redirect_to new_session_path, alert: "Too many sign-in attempts. Please wait a few minutes and try again."
  end
end
