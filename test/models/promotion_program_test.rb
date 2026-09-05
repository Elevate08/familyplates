require "test_helper"

class PromotionProgramTest < ActiveSupport::TestCase
  test "normalizes codes and reports scheduling and redemption limits" do
    program = PromotionProgram.create!(name: "Launch", code: " launch ", discount_percent: 20, max_redemptions: 2)

    assert_equal "LAUNCH", program.code
    assert program.currently_active?
    program.update!(redeemed_count: 2)
    assert_not program.currently_active?
  end
end
