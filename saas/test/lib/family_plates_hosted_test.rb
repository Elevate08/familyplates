require "test_helper"

class FamilyPlatesHostedTest < ActiveSupport::TestCase
  setup do
    FamilyPlates.config.reset!
  end

  teardown do
    FamilyPlates.config.reset!
  end

  # @card-15.7
  test "hosted production refuses to start until SMTP_ADDRESS is set" do
    FamilyPlates.config.mode = "hosted"
    production = ActiveSupport::StringInquirer.new("production")

    with_smtp_env(nil) do
      error = assert_raises(FamilyPlates::OutboundEmailNotConfiguredError) do
        FamilyPlates::OutboundEmail.validate!(environment: production)
      end
      assert_match "SMTP_ADDRESS", error.message
    end

    with_smtp_env("SMTP_ADDRESS" => "smtp.example.com") do
      assert_nothing_raised do
        FamilyPlates::OutboundEmail.validate!(environment: production)
      end
    end
  end

  test "hosted production refuses to start without APP_HOST" do
    FamilyPlates.config.mode = "hosted"
    production = ActiveSupport::StringInquirer.new("production")

    with_smtp_env("APP_HOST" => nil) do
      assert FamilyPlates.hosted_host_missing?(environment: production)
    end

    with_smtp_env("APP_HOST" => "https://plates.example.com/kitchen") do
      assert_equal "plates.example.com", FamilyPlates.public_host
      assert_not FamilyPlates.hosted_host_missing?(environment: production)
    end
  end

  private

  def with_smtp_env(overrides)
    keys = FamilyPlates::OutboundEmail::SMTP_ENV_KEYS + %w[APP_HOST]
    original = keys.to_h { |key| [ key, ENV[key] ] }
    keys.each { |key| ENV.delete(key) }
    overrides&.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    yield
  ensure
    original.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end
end
