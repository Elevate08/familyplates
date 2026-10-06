require "test_helper"
require "open3"

# Nothing else boots the production environment: every other test runs in
# test, and release/v1.3.0 shipped an initializer that could not load in
# production (FamilyPlates was not yet autoloadable). These boot it for real.
class ProductionBootTest < ActiveSupport::TestCase
  PRINT_PROXIES = <<~'RUBY'.freeze
    proxies = Rails.application.config.action_dispatch.trusted_proxies
    puts(proxies ? proxies.map { "#{_1}/#{_1.prefix}" }.join(" ") : "default")
  RUBY

  test "an appliance boots in production with no deployment settings" do
    out, err, status = boot_production("FAMILYPLATES_MODE" => "appliance", "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s)

    assert status.success?, err
    assert_includes out, "booted"
  end

  test "the hosted edition refuses to boot in production without APP_HOST" do
    skip "needs the hosted bundle" unless FamilyPlates.saas?

    _out, err, status = boot_production("FAMILYPLATES_MODE" => "hosted", "SMTP_ADDRESS" => "smtp.example.com")

    assert_not status.success?
    assert_includes err, "APP_HOST is not set"
  end

  test "an appliance in hosted mode says it is the wrong edition before asking for APP_HOST" do
    _out, err, status = boot_production("FAMILYPLATES_MODE" => "hosted", "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s)

    assert_not status.success?
    assert_includes err, "HostedEditionMissingError"
    assert_not_includes err, "APP_HOST is not set"
  end

  test "an image build boots production to precompile assets, without deployment settings" do
    mode = FamilyPlates.saas? ? "hosted" : "appliance"
    out, err, status = boot_production("FAMILYPLATES_MODE" => mode, "SECRET_KEY_BASE_DUMMY" => "1")

    assert status.success?, err
    assert_includes out, "booted"
  end

  test "a staging deploy boots with sandbox keys, its sign-in and its mail sink" do
    skip "needs the hosted bundle" unless FamilyPlates.saas?

    out, err, status = boot_production(staging_env)

    assert status.success?, err
    assert_includes out, "booted"
  end

  test "a staging deploy refuses a live Stripe key without printing it" do
    skip "needs the hosted bundle" unless FamilyPlates.saas?

    _out, err, status = boot_production(staging_env.merge("STRIPE_PRIVATE_KEY" => "sk_live_boot_placeholder"))

    assert_not status.success?
    assert_match(/STRIPE_PRIVATE_KEY.* is not a Stripe test secret or restricted key/, err)
    assert_not_includes err, "sk_live_boot_placeholder"
  end

  test "a staging deploy refuses a publishable key as its private key without printing it" do
    skip "needs the hosted bundle" unless FamilyPlates.saas?

    _out, err, status = boot_production(staging_env.merge("STRIPE_PRIVATE_KEY" => "pk_test_private_slot_placeholder"))

    assert_not status.success?
    assert_match(/STRIPE_PRIVATE_KEY.* is not a Stripe test secret or restricted key/, err)
    assert_not_includes err, "pk_test_private_slot_placeholder"
    assert_not_includes err, "pk_test_boot_placeholder"
  end

  test "a production deploy refuses a publishable key as its private key without printing it" do
    skip "needs the hosted bundle" unless FamilyPlates.saas?

    _out, err, status = boot_production(production_env.merge("STRIPE_PRIVATE_KEY" => "pk_live_private_slot_placeholder"))

    assert_not status.success?
    assert_match(/STRIPE_PRIVATE_KEY.* is not a Stripe live secret or restricted key/, err)
    assert_not_includes err, "pk_live_private_slot_placeholder"
    assert_not_includes err, "pk_live_boot_placeholder"
  end

  test "a hosted production deploy refuses to boot without the encryption settings, naming them" do
    skip "needs the hosted bundle" unless FamilyPlates.saas?

    _out, err, status = boot_production(production_env.merge(
      "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => nil, "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => nil
    ))

    assert_not status.success?
    assert_includes err, "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY is not set"
    assert_includes err, "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT is not set"
    assert_not_includes err, "boot-placeholder"
  end

  test "the saas bundle in production fails closed with no deploy target even if the mode is not hosted" do
    skip "needs the hosted bundle" unless FamilyPlates.saas?

    _out, err, status = boot_production("FAMILYPLATES_MODE" => "appliance", "FAMILYPLATES_DEPLOY_TARGET" => nil,
                                        "BUNDLE_GEMFILE" => Rails.root.join("Gemfile.saas").to_s)

    assert_not status.success?
    assert_includes err, "FAMILYPLATES_DEPLOY_TARGET is not set"
  end

  test "an image build boots with a deploy target and none of its settings" do
    skip "needs the hosted bundle" unless FamilyPlates.saas?

    out, err, status = boot_production("FAMILYPLATES_MODE" => "hosted", "FAMILYPLATES_DEPLOY_TARGET" => "production",
                                       "SECRET_KEY_BASE_DUMMY" => "1")

    assert status.success?, err
    assert_includes out, "booted"
  end

  test "an appliance boots in production trusting loopback only, plus TRUSTED_PROXIES" do
    out, err, status = boot_production({ "FAMILYPLATES_MODE" => "appliance", "TRUSTED_PROXIES" => "172.18.0.5",
                                         "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s }, PRINT_PROXIES)

    assert status.success?, err
    assert_equal "127.0.0.0/8 ::1/128 172.18.0.5/32", out.strip
  end

  test "an appliance refuses to boot when TRUSTED_PROXIES lists a range" do
    _out, err, status = boot_production({ "FAMILYPLATES_MODE" => "appliance", "TRUSTED_PROXIES" => "172.18.0.0/16",
                                          "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s })

    assert_not status.success?
    assert_includes err, "TRUSTED_PROXIES must list single IP addresses"
  end

  test "the hosted edition boots in production with Rails' default trusted proxies" do
    skip "needs the hosted bundle" unless FamilyPlates.saas?

    out, err, status = boot_production(production_env.merge("TRUSTED_PROXIES" => "172.18.0.5"), PRINT_PROXIES)

    assert status.success?, err
    assert_equal "default", out.strip
  end

  private

  def staging_env
    {
      "FAMILYPLATES_MODE" => "hosted", "FAMILYPLATES_DEPLOY_TARGET" => "staging", "APP_HOST" => "dev.familyplates.org",
      "SMTP_ADDRESS" => "smtp.example.net", "STRIPE_PRIVATE_KEY" => "sk_test_boot_placeholder", "STRIPE_SECRET_KEY" => nil,
      # Set, so Pay does not fall back to a key in a developer's credentials.
      "STRIPE_PUBLISHABLE_KEY" => "pk_test_boot_placeholder", "STRIPE_PUBLIC_KEY" => "pk_test_boot_placeholder", "STRIPE_SIGNING_SECRET" => "whsec_boot_placeholder",
      "STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS" => "true", "STRIPE_MONTHLY_PRICE_ID" => "price_test_monthly",
      "STRIPE_ANNUAL_PRICE_ID" => "price_test_annual", "STAGING_ACCESS_USERNAME" => "tester",
      "STAGING_ACCESS_PASSWORD" => "boot-placeholder", "STAGING_MAIL_SINK" => "sink@example.net"
    }.merge(encryption_env)
  end

  def production_env
    {
      "FAMILYPLATES_MODE" => "hosted", "FAMILYPLATES_DEPLOY_TARGET" => "production", "APP_HOST" => "familyplates.org",
      "SMTP_ADDRESS" => "smtp.example.net", "STRIPE_PRIVATE_KEY" => "sk_live_boot_placeholder", "STRIPE_SECRET_KEY" => nil,
      # Set, so Pay does not fall back to a key in a developer's credentials.
      "STRIPE_PUBLISHABLE_KEY" => "pk_live_boot_placeholder", "STRIPE_PUBLIC_KEY" => "pk_live_boot_placeholder", "STRIPE_SIGNING_SECRET" => "whsec_boot_placeholder",
      "STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS" => "false", "STRIPE_MONTHLY_PRICE_ID" => "price_live_monthly",
      "STRIPE_ANNUAL_PRICE_ID" => "price_live_annual", "STAGING_ACCESS_USERNAME" => nil, "STAGING_ACCESS_PASSWORD" => nil,
      "STAGING_MAIL_SINK" => nil, "STAGING_MAIL_ALLOWLIST" => nil
    }.merge(encryption_env)
  end

  def encryption_env
    { "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "boot-placeholder-primary", "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => "boot-placeholder-salt" }
  end

  def boot_production(env, script = "puts :booted")
    clean = { "RAILS_ENV" => "production", "APP_HOST" => nil, "SMTP_ADDRESS" => nil, "SECRET_KEY_BASE_DUMMY" => "1",
              "BUNDLE_GEMFILE" => ENV["BUNDLE_GEMFILE"] }.merge(env)
    clean["SECRET_KEY_BASE_DUMMY"] = nil unless env.key?("SECRET_KEY_BASE_DUMMY")
    clean["SECRET_KEY_BASE"] = "x" * 64 if clean["SECRET_KEY_BASE_DUMMY"].nil?
    Bundler.with_unbundled_env do
      Open3.capture3(clean, Rails.root.join("bin/rails").to_s, "runner", script, chdir: Rails.root.to_s)
    end
  end
end
