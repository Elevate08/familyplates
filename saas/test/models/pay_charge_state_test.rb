# frozen_string_literal: true

require "test_helper"

class PayChargeStateTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
    @household.set_payment_processor :fake_processor, allow_fake: true
    @customer = @household.payment_processor
  end

  # @card-23.8
  test "each Stripe charge state has one operator label" do
    cases = {
      "ch_paid" => [ { "status" => "succeeded", "captured" => true, "disputed" => false, "refunded" => false }, 400, 0, :paid, "Paid" ],
      "ch_legacy" => [ {}, 400, 0, :paid, "Paid" ],
      "ch_failed" => [ { "status" => "failed", "failure_code" => "card_declined" }, 400, 0, :failed, "Failed" ],
      "ch_pending" => [ { "status" => "pending" }, 400, 0, :pending, "Pending" ],
      "ch_uncaptured" => [ { "status" => "succeeded", "captured" => false }, 400, 0, :uncaptured, "Uncaptured" ],
      "ch_partial" => [ { "status" => "succeeded", "captured" => true, "refunded" => false }, 400, 100, :partially_refunded, "Partially refunded" ],
      "ch_refunded" => [ { "status" => "succeeded", "captured" => true, "refunded" => true }, 400, 400, :refunded, "Refunded" ],
      "ch_disputed" => [ { "status" => "succeeded", "captured" => true, "disputed" => true, "dispute" => "dp_123", "refunded" => true }, 400, 400, :disputed, "Disputed" ]
    }

    cases.each do |processor_id, (object, amount, refunded, key, label)|
      charge = @customer.charges.create!(
        processor_id: processor_id,
        amount: amount,
        amount_refunded: refunded,
        currency: "usd",
        object: object
      )
      state = PayChargeState.for(charge)

      assert_equal key, state.key, processor_id
      assert_equal label, state.label, processor_id
    end
  end

  # @card-42.1
  test "an unrecognised charge status is shown rather than called Paid" do
    charge = @customer.charges.create!(
      processor_id: "ch_other",
      amount: 400,
      currency: "usd",
      object: { "status" => "requires_action" }
    )

    state = PayChargeState.for(charge)
    assert_equal :other, state.key
    assert_equal "Requires action", state.label
  end
end
