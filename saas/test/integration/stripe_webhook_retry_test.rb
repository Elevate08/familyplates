# frozen_string_literal: true

require "test_helper"

# Pay answers Stripe before it processes an event, so a processing failure is
# never redelivered. A transient Stripe failure must be retried by the job,
# and a row that still fails must stay behind rather than vanish.
class StripeWebhookRetryTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @webhook = Pay::Webhook.create!(
      processor: "stripe", event_type: "customer.subscription.updated",
      event: { "id" => "evt_retry", "type" => "customer.subscription.updated", "data" => { "object" => { "id" => "sub_retry" } } }
    )
  end

  [ ::Stripe::APIConnectionError, ::Stripe::RateLimitError, ::Stripe::APIError ].each do |error|
    test "#{error.name} while processing is retried, then surfaces with the row kept" do
      attempts = 0
      with_processing_raising(-> { attempts += 1; raise error, "synthetic" }) do
        assert_kind_of error, job_error { Pay::Webhooks::ProcessJob.perform_later(@webhook) }
      end

      assert_equal StripeWebhookRetries::ATTEMPTS, attempts
      assert Pay::Webhook.exists?(@webhook.id), "a webhook that never processed stays as a backlog"
    end
  end

  test "a failure that retrying cannot fix is not retried" do
    attempts = 0
    with_processing_raising(-> { attempts += 1; raise ::Stripe::InvalidRequestError.new("synthetic", nil) }) do
      assert_kind_of ::Stripe::InvalidRequestError, job_error { Pay::Webhooks::ProcessJob.perform_later(@webhook) }
    end

    assert_equal 1, attempts
  end

  test "a transient failure that clears processes the event and removes the row" do
    attempts = 0
    with_processing_raising(-> { attempts += 1; raise ::Stripe::APIConnectionError, "synthetic" if attempts == 1 }) do
      perform_enqueued_jobs { Pay::Webhooks::ProcessJob.perform_later(@webhook) }
    end

    assert_equal 2, attempts
    assert_not Pay::Webhook.exists?(@webhook.id)
  end

  private

  # perform_enqueued_jobs wraps an exception a job raises; returns the job's own.
  def job_error(&block)
    assert_raises(Minitest::UnexpectedError) { perform_enqueued_jobs(&block) }.error
  end

  # Every Pay::Webhook the job loads runs this instead of processing; on the
  # call that does not raise, the row is destroyed as process! would.
  def with_processing_raising(behavior)
    Pay::Webhook.alias_method :__original_process!, :process!
    Pay::Webhook.define_method(:process!) do
      behavior.call
      destroy
    end
    yield
  ensure
    Pay::Webhook.alias_method :process!, :__original_process!
    Pay::Webhook.remove_method :__original_process!
  end
end
