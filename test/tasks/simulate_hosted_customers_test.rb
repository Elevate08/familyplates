require "test_helper"
require "rake"

class SimulateHostedCustomersRakeTest < ActiveSupport::TestCase
  setup do
    @previous_secret = ENV["STRIPE_SECRET_KEY"]
    @previous_private = ENV["STRIPE_PRIVATE_KEY"]
    @previous_rake = Rake.application
    @rake = Rake::Application.new
    Rake.application = @rake
    Rake::Task.define_task(:environment)
    load Rails.root.join("lib/tasks/simulate_hosted_customers.rake")
  end

  teardown do
    Rake.application = @previous_rake
    ENV["STRIPE_SECRET_KEY"] = @previous_secret
    ENV["STRIPE_PRIVATE_KEY"] = @previous_private
  end

  test "aborts when the Stripe key is a live secret" do
    ENV["STRIPE_SECRET_KEY"] = "sk_live_not_a_real_key"
    ENV.delete("STRIPE_PRIVATE_KEY")

    error = assert_raises(SystemExit) do
      capture_io { @rake["hosted:simulate_customers"].invoke }
    end
    assert_match(/sk_test_/, error.message)
  end

  test "aborts in production even with a test key" do
    previous_env = Rails.env.to_s
    ENV["STRIPE_SECRET_KEY"] = "sk_test_not_a_real_key"
    ENV.delete("STRIPE_PRIVATE_KEY")

    error = assert_raises(SystemExit) do
      Rails.env = "production"
      capture_io { @rake["hosted:simulate_customers"].invoke }
    end
    assert_match(/non-production/, error.message)
  ensure
    Rails.env = previous_env if previous_env
  end
end
