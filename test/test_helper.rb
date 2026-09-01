ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # PIN throttle counters live in a process-wide store, so without this a test
    # that signs in repeatedly would spend the next test's attempt budget.
    setup { Rails.application.config.pin_attempt_store.clear }

    # Add more helper methods to be used by all tests here...
  end
end
