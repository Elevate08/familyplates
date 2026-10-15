# frozen_string_literal: true

require "test_helper"

class BillingOfferTest < ActiveSupport::TestCase
  # Shown beside the annual price; it must agree with what Stripe's Checkout
  # shows ($50 / 12 = $4.1667 is $4.17), not truncate to a cheaper-looking $4.16.
  test "the monthly equivalent of a yearly price is rounded to the nearest cent" do
    assert_equal "$4.17", BillingOffer.for(:annual).monthly_equivalent
    assert_equal "$5.00", BillingOffer.for(:monthly).monthly_equivalent
  end

  test "the annual saving is a whole percent, never overstated" do
    assert_equal 16, BillingOffer.for(:annual).savings_percent_against(BillingOffer.for(:monthly))
  end
end
