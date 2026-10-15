require "test_helper"

class DeployTargetTest < ActiveSupport::TestCase
  PRODUCTION = ActiveSupport::EnvironmentInquirer.new("production")
  LIVE_KEY = "sk_live_placeholder_value"
  TEST_KEY = "sk_test_placeholder_value"
  SECRET_KEY_SOURCES = FamilyPlatesSaas::DeployTarget::SECRET_KEY_SOURCES
  PUBLISHABLE_KEY_SOURCES = FamilyPlatesSaas::DeployTarget::PUBLISHABLE_KEY_SOURCES

  test "production boots with live keys and live webhooks only" do
    assert_empty problems(production_env, LIVE_KEY)
  end

  test "staging boots with sandbox keys, test webhooks, its sign-in and its mail routing" do
    assert_empty problems(staging_env, TEST_KEY)
  end

  test "production refuses a sandbox key, staging refuses a live one, without printing either" do
    { production_env => TEST_KEY, staging_env => LIVE_KEY }.each do |env, key|
      found = problems(env, key).join("\n")
      assert_includes found, "STRIPE_PRIVATE_KEY is not a Stripe"
      assert_not_includes found, key
    end
  end

  test "a wrong-mode publishable key or Pay credential is refused too" do
    found = problems(production_env, LIVE_KEY, "STRIPE_PUBLISHABLE_KEY" => "pk_test_x", "Pay public_key" => "pk_test_x")
    assert_match(/STRIPE_PUBLISHABLE_KEY, Pay public_key is not a Stripe live publishable key/, found.join)
  end

  test "each key setting accepts its own role in the deploy's mode" do
    { production_env => "live", staging_env => "test" }.each do |env, mode|
      %w[sk rk].each do |role|
        keys = SECRET_KEY_SOURCES.index_with { placeholder(role, mode) }
          .merge(PUBLISHABLE_KEY_SOURCES.index_with { placeholder("pk", mode) })
        assert_empty problems_with(env, keys), "#{role}_#{mode}_ secret keys with pk_#{mode}_ publishable keys"
      end
    end
  end

  test "a secret key setting refuses a publishable key or another mode's key, without printing it" do
    { production_env => %w[live test], staging_env => %w[test live] }.each do |env, (mode, other)|
      [ placeholder("pk", mode), placeholder("pk", other), placeholder("sk", other), placeholder("rk", other) ].each do |bad|
        SECRET_KEY_SOURCES.each do |source|
          # The other secret settings hold a good key: every present key is checked.
          keys = SECRET_KEY_SOURCES.index_with { placeholder("sk", mode) }.merge(source => bad)
          found = problems_with(env, keys).join("\n")

          assert_includes found, "#{source} is not a Stripe #{mode} secret or restricted key", "#{bad} in #{source}"
          assert_not_includes found, bad
        end
      end
    end
  end

  test "a publishable key setting refuses a secret or restricted key, or another mode's key, without printing it" do
    { production_env => %w[live test], staging_env => %w[test live] }.each do |env, (mode, other)|
      bad_keys = [ placeholder("sk", mode), placeholder("rk", mode), placeholder("sk", other), placeholder("rk", other), placeholder("pk", other) ]
      bad_keys.each do |bad|
        PUBLISHABLE_KEY_SOURCES.each do |source|
          keys = { "STRIPE_PRIVATE_KEY" => placeholder("sk", mode), source => bad }
          found = problems_with(env, keys).join("\n")

          assert_includes found, "#{source} is not a Stripe #{mode} publishable key", "#{bad} in #{source}"
          assert_not_includes found, bad
        end
      end
    end
  end

  test "publishable keys alone do not stand in for the secret key" do
    keys = PUBLISHABLE_KEY_SOURCES.index_with { placeholder("pk", "live") }
    assert_includes problems_with(production_env, keys).join("\n"), "STRIPE_PRIVATE_KEY is not set"
  end

  test "a key from a setting with no known role is refused" do
    found = problems_with(production_env, "STRIPE_PRIVATE_KEY" => LIVE_KEY, "STRIPE_OTHER_KEY" => "sk_live_other_placeholder").join("\n")

    assert_includes found, "STRIPE_OTHER_KEY is not a Stripe key setting"
    assert_not_includes found, "sk_live_other_placeholder"
  end

  test "each target refuses the other's webhook event mode" do
    found = problems(production_env.merge("STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS" => "true"), LIVE_KEY)
    assert_includes found, "STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS must be false on the production deploy."

    found = problems(staging_env.merge("STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS" => "false"), TEST_KEY)
    assert_includes found, "STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS must be true on the staging deploy."

    found = problems(production_env.except("STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS"), LIVE_KEY)
    assert_includes found, "STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS must be false on the production deploy."
  end

  test "missing Stripe settings are refused rather than left to fail at checkout" do
    env = production_env.except("STRIPE_SIGNING_SECRET", "STRIPE_ANNUAL_PRICE_ID")
    found = problems(env, nil).join("\n")

    assert_includes found, "STRIPE_PRIVATE_KEY is not set"
    assert_includes found, "STRIPE_SIGNING_SECRET is not set"
    assert_includes found, "STRIPE_ANNUAL_PRICE_ID must name a Stripe live-mode price"
  end

  test "staging will not start open to the internet or able to mail anyone" do
    env = staging_env.except("STAGING_ACCESS_PASSWORD", "STAGING_MAIL_SINK", "STAGING_MAIL_ALLOWLIST")
    found = problems(env, TEST_KEY).join("\n")

    assert_includes found, "STAGING_ACCESS_PASSWORD is not set"
    assert_includes found, "STAGING_MAIL_SINK or STAGING_MAIL_ALLOWLIST is required"
  end

  test "production refuses staging's settings, which would mean the two were crossed" do
    env = production_env.merge("STAGING_ACCESS_USERNAME" => "tester", "STAGING_MAIL_SINK" => "sink@example.com")
    assert_includes problems(env, LIVE_KEY),
      "STAGING_ACCESS_USERNAME, STAGING_MAIL_SINK belongs to the staging deploy and must not be set on production."
  end

  test "an unknown target is refused" do
    assert_equal [ "FAMILYPLATES_DEPLOY_TARGET must be production or staging." ],
      problems(production_env.merge("FAMILYPLATES_DEPLOY_TARGET" => "prod"), LIVE_KEY)
  end

  test "production with no target fails closed, naming the variable" do
    found = problems(production_env.except("FAMILYPLATES_DEPLOY_TARGET"), TEST_KEY)
    assert_equal 1, found.size
    assert_includes found.first, "FAMILYPLATES_DEPLOY_TARGET is not set"
    assert_not_includes found.first, TEST_KEY

    assert_raises(FamilyPlatesSaas::DeployTargetError) do
      FamilyPlatesSaas::DeployTarget.verify!(
        environment: PRODUCTION, env: production_env.except("FAMILYPLATES_DEPLOY_TARGET").merge(encryption_env), keys: { "STRIPE_PRIVATE_KEY" => LIVE_KEY }
      )
    end
  end

  test "production with a blank target fails closed even when hosted mode is off" do
    FamilyPlates.config.reset!
    assert_not FamilyPlates.config.hosted?

    error = assert_raises(FamilyPlatesSaas::DeployTargetError) do
      FamilyPlatesSaas::DeployTarget.verify!(
        environment: PRODUCTION, env: production_env.merge(encryption_env, "FAMILYPLATES_DEPLOY_TARGET" => ""), keys: { "STRIPE_PRIVATE_KEY" => LIVE_KEY }
      )
    end
    assert_includes error.message, "FAMILYPLATES_DEPLOY_TARGET is not set"
  end

  test "production with the target and valid shape still verifies" do
    assert_nothing_raised do
      FamilyPlatesSaas::DeployTarget.verify!(
        environment: PRODUCTION, env: production_env.merge(encryption_env), keys: { "STRIPE_PRIVATE_KEY" => LIVE_KEY }
      )
    end
  end

  test "production refuses to boot without the Active Record encryption settings, naming them not values" do
    error = assert_raises(FamilyPlatesSaas::DeployTargetError) do
      FamilyPlatesSaas::DeployTarget.verify!(environment: PRODUCTION, env: production_env, keys: { "STRIPE_PRIVATE_KEY" => LIVE_KEY })
    end
    assert_includes error.message, "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"
    assert_includes error.message, "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"
  end

  test "outside production no target is left as before" do
    %w[test development].each do |name|
      assert_empty FamilyPlatesSaas::DeployTarget.problems(
        environment: ActiveSupport::EnvironmentInquirer.new(name), env: production_env, keys: { "STRIPE_PRIVATE_KEY" => TEST_KEY }
      )
    end
  end

  test "verify! raises with every problem, and the gate applies to staging only" do
    error = assert_raises(FamilyPlatesSaas::DeployTargetError) do
      FamilyPlatesSaas::DeployTarget.verify!(environment: PRODUCTION, env: staging_env, keys: { "STRIPE_PRIVATE_KEY" => LIVE_KEY })
    end
    assert_includes error.message, "STRIPE_PRIVATE_KEY"

    assert FamilyPlatesSaas::DeployTarget.staging?(environment: PRODUCTION, env: staging_env)
    assert_not FamilyPlatesSaas::DeployTarget.staging?(environment: PRODUCTION, env: production_env)
    assert_not FamilyPlatesSaas::DeployTarget.staging?(environment: ActiveSupport::EnvironmentInquirer.new("test"), env: staging_env)
  end

  private

  def problems(env, key, extra_keys = {})
    problems_with(env, { "STRIPE_PRIVATE_KEY" => key }.merge(extra_keys))
  end

  def problems_with(env, keys)
    FamilyPlatesSaas::DeployTarget.problems(environment: PRODUCTION, env: env, keys: keys)
  end

  def encryption_env
    { "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY" => "placeholder-primary", "ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT" => "placeholder-salt" }
  end

  def placeholder(role, mode)
    "#{role}_#{mode}_placeholder_value"
  end

  def production_env
    {
      "FAMILYPLATES_DEPLOY_TARGET" => "production",
      "STRIPE_SIGNING_SECRET" => "whsec_placeholder",
      "STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS" => "false",
      "STRIPE_MONTHLY_PRICE_ID" => "price_monthly",
      "STRIPE_ANNUAL_PRICE_ID" => "price_annual"
    }
  end

  def staging_env
    production_env.merge(
      "FAMILYPLATES_DEPLOY_TARGET" => "staging",
      "STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS" => "true",
      "STAGING_ACCESS_USERNAME" => "tester",
      "STAGING_ACCESS_PASSWORD" => "placeholder",
      "STAGING_MAIL_SINK" => "sink@example.com"
    )
  end
end
