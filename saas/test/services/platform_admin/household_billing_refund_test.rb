# frozen_string_literal: true

require "test_helper"

class PlatformAdmin::HouseholdBillingRefundTest < ActiveSupport::TestCase
  setup do
    FamilyPlates.config.mode = "hosted"
    @household = households(:one)
    @household.set_payment_processor :fake_processor, allow_fake: true
    @charge = @household.payment_processor.charges.create!(
      processor_id: "ch_refund", amount: 5000, amount_refunded: 0, currency: "usd"
    )
    @billing = PlatformAdmin::HouseholdBilling.new(@household)
  end

  teardown { FamilyPlates.config.reset! }

  test "a partial refund within what is left goes through" do
    assert_equal 1000, @billing.refund_charge!(@charge.id, amount_cents: 1000)
    assert_equal 1000, @charge.reload.amount_refunded
  end

  test "a refund larger than what is left is refused" do
    @charge.update_columns(amount_refunded: 4500)

    error = assert_raises(PlatformAdmin::HouseholdBilling::Error) { @billing.refund_charge!(@charge.id, amount_cents: 1000) }
    assert_match "$5.00", error.message
  end

  # Two operators refunding the same charge at once: each request read the
  # charge before the other's refund was recorded. The second must be bounded
  # by what is left after the first, not by the amount it read.
  test "a refund recorded after this request read the charge still bounds it" do
    stale = Pay::Charge.find(@charge.id)
    Pay::Charge.where(id: @charge.id).update_all(amount_refunded: 4500)

    finder = Object.new
    finder.define_singleton_method(:find) { |_id| stale }
    @household.define_singleton_method(:pay_charges) { finder }

    error = assert_raises(PlatformAdmin::HouseholdBilling::Error) { @billing.refund_charge!(@charge.id, amount_cents: 1000) }
    assert_match "$5.00", error.message
    assert_equal 4500, @charge.reload.amount_refunded
  end
end
