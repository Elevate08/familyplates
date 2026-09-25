require "test_helper"

class StripeSandboxTest < ActiveSupport::TestCase
  test "the test environment refuses a live Stripe key from any source" do
    test_env = ActiveSupport::EnvironmentInquirer.new("test")

    [ "sk_live_x", "rk_live_x", "pk_live_x", "not-a-stripe-key" ].each do |key|
      error = assert_raises(FamilyPlatesSaas::LiveStripeKeyError) do
        FamilyPlatesSaas::StripeSandbox.verify!(environment: test_env, keys: { "STRIPE_SECRET_KEY" => key })
      end
      assert_includes error.message, "STRIPE_SECRET_KEY"
      assert_not_includes error.message, key, "the key itself must not end up in a CI log"
    end
  end

  test "the test environment accepts sandbox keys and no key at all" do
    test_env = ActiveSupport::EnvironmentInquirer.new("test")

    [ "sk_test_x", "rk_test_x", "pk_test_x", nil, "" ].each do |key|
      assert_nothing_raised do
        FamilyPlatesSaas::StripeSandbox.verify!(environment: test_env, keys: { "STRIPE_SECRET_KEY" => key })
      end
    end
  end

  test "the Stripe sandbox check leaves other environments alone" do
    %w[development production].each do |name|
      assert_nothing_raised do
        FamilyPlatesSaas::StripeSandbox.verify!(
          environment: ActiveSupport::EnvironmentInquirer.new(name), keys: { "STRIPE_SECRET_KEY" => "sk_live_x" }
        )
      end
    end
  end
end
