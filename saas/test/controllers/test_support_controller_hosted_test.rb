require "test_helper"

# The endpoints the Playwright suite drives. Most of it is exercised by every
# E2E run; what is covered here fails in ways a run shows only later or
# somewhere else - a clock that stops freezing turns baselines stale a week on,
# and a reset that cannot clear billing fails every test after the payment.
class HostedTestSupportControllerHostedTest < ActionDispatch::IntegrationTest
  FROZEN = "2026-09-22T12:00:00.000Z".freeze

  teardown { TestSupportController::CLOCK.travel_back }

  test "reset clears a paid subscription, its charge and its card" do
    household = households(:one)
    household.set_payment_processor :fake_processor, allow_fake: true
    customer = household.payment_processor
    subscription = customer.subscriptions.create!(
      name: "default", processor_id: "sub_paid", processor_plan: "annual", status: "active"
    )
    customer.charges.create!(processor_id: "ch_paid", amount: 3500, subscription: subscription)
    customer.payment_methods.create!(processor_id: "pm_card", default: true, payment_method_type: "card")

    post "/__test/reset", as: :json

    assert_response :success
    assert_equal 0, Pay::Charge.count + Pay::PaymentMethod.count + Pay::Subscription.count + Pay::Customer.count
  end
end
