require "test_helper"

# The endpoints the Playwright suite drives. Most of it is exercised by every
# E2E run; what is covered here fails in ways a run shows only later or
# somewhere else - a clock that stops freezing turns baselines stale a week on,
# and a reset that cannot clear billing fails every test after the payment.
class TestSupportControllerTest < ActionDispatch::IntegrationTest
  FROZEN = "2026-09-22T12:00:00.000Z".freeze

  teardown { TestSupportController::CLOCK.travel_back }

  test "reset freezes the server clock at the requested moment" do
    post "/__test/reset", params: { now: FROZEN }, as: :json

    assert_response :success
    assert_equal Time.iso8601(FROZEN), Time.current
    assert_equal Date.new(2026, 9, 22), Date.current
  end

  test "reset without a moment lets the clock run" do
    TestSupportController::CLOCK.travel_to(Time.iso8601(FROZEN))

    post "/__test/reset", as: :json

    assert_response :success
    assert_operator Time.current, :>, Time.iso8601(FROZEN) + 1.day
  end
end
