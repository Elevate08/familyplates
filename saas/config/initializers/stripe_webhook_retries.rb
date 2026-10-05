# frozen_string_literal: true

# Pay answers Stripe 200 before it processes an event, so Stripe never
# redelivers one whose processing failed, and StripeWebhookReplayGuard would
# refuse a redelivery anyway. Pay::Webhooks::ProcessJob has no retry of its
# own: one Stripe timeout or rate limit while syncing would leave a
# subscription or charge out of step with Stripe until a later event happened
# to fix it. Transient failures are retried with backoff (about four hours
# across all attempts). Anything else, or the last attempt, fails the job; the
# Pay::Webhook row is destroyed only after it processes, so a failure stays
# behind as a visible backlog.
module StripeWebhookRetries
  ATTEMPTS = 10
  TRANSIENT_ERRORS = [ ::Stripe::APIConnectionError, ::Stripe::RateLimitError, ::Stripe::APIError ].freeze

  def self.included(job)
    job.retry_on(*TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: ATTEMPTS)
  end
end

Rails.application.config.to_prepare do
  job = Pay::Webhooks::ProcessJob
  job.include(StripeWebhookRetries) unless job.include?(StripeWebhookRetries)
end
