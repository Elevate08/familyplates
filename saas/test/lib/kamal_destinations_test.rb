require "test_helper"
require "kamal"

# Resolves the real Kamal config for each destination with placeholder inputs,
# the way `bin/kamal <command> -d <destination>` does, and checks the two can
# never share a service, host, volume, secret input, Stripe mode or SMTP
# account. Nothing here connects to a server.
class KamalDestinationsTest < ActiveSupport::TestCase
  DESTINATIONS = %w[production staging].freeze
  CONFIG_DIR = Rails.root.join("saas/config")
  SECRETS_PATH = Rails.root.join("saas/.kamal/secrets")
  SECRET_NAMES = %w[
    SECRET_KEY_BASE ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
    SMTP_USERNAME SMTP_PASSWORD STRIPE_PRIVATE_KEY STRIPE_SIGNING_SECRET
  ].freeze
  STAGING_SECRET_NAMES = %w[STAGING_ACCESS_USERNAME STAGING_ACCESS_PASSWORD].freeze

  # Synthetic secrets files (env references only, never values) so the suite can
  # resolve each destination where the real ones are deliberately absent. Written
  # once before the test workers fork, and removed afterwards by the process that
  # created them; a file that already exists is never read or overwritten.
  SYNTHETIC_SECRET_FILES = DESTINATIONS.each_with_object([]) do |destination, created|
    file = "#{SECRETS_PATH}.#{destination}"
    next if File.exist?(file)

    names = SECRET_NAMES + (destination == "staging" ? STAGING_SECRET_NAMES : [])
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, names.map { |name| "#{name}=$FAMILYPLATES_#{destination.upcase}_#{name.delete_prefix('STAGING_')}\n" }.join)
    created << file
  end.freeze
  CREATOR_PID = Process.pid
  Minitest.after_run { SYNTHETIC_SECRET_FILES.each { |file| FileUtils.rm_f(file) } if Process.pid == CREATOR_PID }

  setup do
    @saved_env = ENV.to_h
    placeholder_inputs.each { |name, value| ENV[name] = value }
  end

  teardown do
    ENV.replace(@saved_env)
  end

  test "each destination is its own service, image, host and volume" do
    production, staging = DESTINATIONS.map { |destination| resolve(destination) }

    assert_equal "familyplates-production", production[:config].service
    assert_equal "familyplates-staging", staging[:config].service
    assert_equal "familyplates-production", production[:raw]["image"]
    assert_equal "familyplates-staging", staging[:raw]["image"]
    assert_equal "familyplates.org", production[:raw].dig("proxy", "host")
    assert_equal "dev.familyplates.org", staging[:raw].dig("proxy", "host")
    assert_equal [ "203.0.113.10" ], production[:raw].dig("servers", "web", "hosts")
    assert_equal [ "203.0.113.11" ], staging[:raw].dig("servers", "web", "hosts")
    # A host folder on each server's attached data disk, so the databases survive
    # replacing the server and are snapshotted apart from it.
    assert_equal [ "/srv/familyplates-production/storage:/rails/storage" ], production[:raw]["volumes"]
    assert_equal [ "/srv/familyplates-staging/storage:/rails/storage" ], staging[:raw]["volumes"]
  end

  test "both run the hosted edition as RAILS_ENV production, each naming its own target" do
    DESTINATIONS.each do |destination|
      resolved = resolve(destination)
      assert_equal "hosted", resolved[:raw].dig("builder", "args", "EDITION")
      assert_equal "production", resolved[:clear]["RAILS_ENV"]
      assert_equal destination, resolved[:clear]["FAMILYPLATES_DEPLOY_TARGET"]
      assert_equal resolved[:raw].dig("proxy", "host"), resolved[:clear]["APP_HOST"]
    end
  end

  test "each destination reads only its own secret inputs" do
    DESTINATIONS.each do |destination|
      secrets = resolve(destination)[:config].secrets
      names = SECRET_NAMES + (destination == "staging" ? STAGING_SECRET_NAMES : [])

      names.each do |name|
        assert_equal placeholder(destination, name), secrets[name], "#{destination} #{name}"
      end
    end

    DESTINATIONS.each do |destination|
      lines = File.readlines("#{SECRETS_PATH}.#{destination}").map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
      lines.each do |line|
        name, source = line.split("=", 2)
        assert_equal "$FAMILYPLATES_#{destination.upcase}_#{name.delete_prefix('STAGING_')}", source,
          "#{destination}: #{name} must come from its own FAMILYPLATES_#{destination.upcase}_ input"
      end
    end
  end

  test "no secrets file or .env is shared between destinations" do
    assert_not File.exist?("#{SECRETS_PATH}-common"), "Kamal merges secrets-common into every destination"
    assert_not File.exist?(SECRETS_PATH.to_s), "an undestined secrets file is a shared default"

    %w[deploy.yml deploy.production.yml deploy.staging.yml].each do |file|
      code = CONFIG_DIR.join(file).read.scan(/<%(.*?)%>/m).join("\n")
      assert_no_match(/\b(Dotenv|load|require|File|IO)\b|\.env/, code, "#{file} must read nothing but ENV")
    end
    production_source = CONFIG_DIR.join("deploy.production.yml").read
    staging_source = CONFIG_DIR.join("deploy.staging.yml").read
    assert_no_match(/FAMILYPLATES_STAGING_/, production_source)
    assert_no_match(/FAMILYPLATES_PRODUCTION_/, staging_source)
  end

  # FP-APPSEC-012, accepted risk: kamal-proxy logs calendar-feed and transfer
  # tokens in request paths. That is accepted only while its log stays on the
  # host, readable by no one who could not already read the database, and
  # rotated by Kamal's default size cap. Sending it anywhere else (a log driver
  # option, a shipping driver) reopens the finding; change this test only
  # after revisiting it.
  test "the proxy log stays on the host with Kamal's default rotation" do
    [ "deploy.yml", "deploy.production.yml", "deploy.staging.yml" ].each do |file|
      assert_no_match(/^\s*log-(driver|opt):/, CONFIG_DIR.join(file).read, file)
    end
    DESTINATIONS.each do |destination|
      resolved = resolve(destination)
      assert_nil resolved[:raw].dig("proxy", "run", "options"), destination

      host = resolved[:raw].dig("servers", "web", "hosts").first
      rendered = Kamal::Commands::Proxy.new(resolved[:config], host: host).run.join(" ")
      assert_no_match(/--log-driver/, rendered, "#{destination} proxy uses Docker's default local driver")
      assert_includes rendered, "--log-opt max-size=#{Kamal::Configuration::Proxy::Run::DEFAULT_LOG_MAX_SIZE}", destination
    end
  end

  test "a deploy must name its destination" do
    error = assert_raises(StandardError) { Kamal::Configuration.create_from(config_file: CONFIG_DIR.join("deploy.yml"), version: "test") }
    assert_match(/destination/i, error.message)
  end

  test "production takes live webhooks only and staging the sandbox's" do
    production, staging = DESTINATIONS.map { |destination| resolve(destination) }

    assert_equal "false", production[:clear]["STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS"]
    assert_equal "true", staging[:clear]["STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS"]
    assert_not_equal production[:config].secrets["STRIPE_SIGNING_SECRET"], staging[:config].secrets["STRIPE_SIGNING_SECRET"]
    %w[STRIPE_MONTHLY_PRICE_ID STRIPE_ANNUAL_PRICE_ID].each do |name|
      assert_not_equal production[:clear][name], staging[:clear][name]
    end
  end

  test "each resolved destination boots only with its own Stripe key mode" do
    keys = { "production" => "sk_live_placeholder", "staging" => "sk_test_placeholder" }

    DESTINATIONS.each do |destination|
      resolved = resolve(destination)
      env = container_env(resolved, destination)
      own, other = keys[destination], keys.except(destination).values.first

      assert_empty problems(env, own), "#{destination} with its own key mode"
      assert_not_empty problems(env, other), "#{destination} with the other's key mode"
    end
  end

  test "SMTP accounts are separate and staging mail is held to its sink" do
    production, staging = DESTINATIONS.map { |destination| resolve(destination) }

    assert_not_equal production[:clear]["SMTP_ADDRESS"], staging[:clear]["SMTP_ADDRESS"]
    %w[SMTP_USERNAME SMTP_PASSWORD].each do |name|
      assert_not_equal production[:config].secrets[name], staging[:config].secrets[name]
    end
    assert_equal "sink@example.net", staging[:clear]["STAGING_MAIL_SINK"]
    assert_equal "tester@example.net", staging[:clear]["STAGING_MAIL_ALLOWLIST"]
    assert_empty production[:clear].keys.grep(/\ASTAGING_/)
    assert_empty production[:raw].dig("env", "secret").grep(/\ASTAGING_/)
  end

  test "containers are capped and mount nothing but their own volume" do
    DESTINATIONS.each do |destination|
      raw = resolve(destination)[:raw]
      options = raw.dig("servers", "web", "options")

      assert options["memory"].present?, "#{destination} memory limit"
      assert options["cpus"].present?, "#{destination} CPU limit"
      assert options["pids-limit"].present?, "#{destination} process limit"
      assert_empty options.keys & %w[volume mount privileged network pid], "#{destination} options"
      assert_no_match(/docker\.sock|familyplates_(?!#{destination}_)\w+_storage/, raw.to_s)
    end
  end

  private

  def resolve(destination)
    config = Dir.chdir(Rails.root) do
      Kamal::Configuration.create_from(config_file: CONFIG_DIR.join("deploy.yml"), destination: destination, version: "test")
    end
    raw = config.raw_config.to_h.deep_stringify_keys
    { config: config, raw: raw, clear: raw.dig("env", "clear").transform_values(&:to_s) }
  ensure
    ENV.delete("KAMAL_DESTINATION")
  end

  # The env a destination's container starts with, with placeholder secrets of
  # the right shape where the boot check looks at their shape.
  def container_env(resolved, destination)
    resolved[:clear].merge(
      "STRIPE_SIGNING_SECRET" => "whsec_placeholder",
      "STAGING_ACCESS_USERNAME" => (placeholder(destination, "STAGING_ACCESS_USERNAME") if destination == "staging"),
      "STAGING_ACCESS_PASSWORD" => (placeholder(destination, "STAGING_ACCESS_PASSWORD") if destination == "staging")
    ).compact
  end

  def problems(env, key)
    FamilyPlatesSaas::DeployTarget.problems(
      environment: ActiveSupport::EnvironmentInquirer.new("production"), env: env, keys: { "STRIPE_PRIVATE_KEY" => key }
    )
  end

  def placeholder(destination, name)
    "placeholder-#{destination}-#{name.downcase}"
  end

  def placeholder_inputs
    inputs = {
      "FAMILYPLATES_PRODUCTION_SERVER" => "203.0.113.10",
      "FAMILYPLATES_PRODUCTION_SMTP_ADDRESS" => "smtp.example.com",
      "FAMILYPLATES_PRODUCTION_STRIPE_MONTHLY_PRICE_ID" => "price_live_monthly",
      "FAMILYPLATES_PRODUCTION_STRIPE_ANNUAL_PRICE_ID" => "price_live_annual",
      "FAMILYPLATES_STAGING_SERVER" => "203.0.113.11",
      "FAMILYPLATES_STAGING_SMTP_ADDRESS" => "smtp.example.net",
      "FAMILYPLATES_STAGING_STRIPE_MONTHLY_PRICE_ID" => "price_test_monthly",
      "FAMILYPLATES_STAGING_STRIPE_ANNUAL_PRICE_ID" => "price_test_annual",
      "FAMILYPLATES_STAGING_MAIL_SINK" => "sink@example.net",
      "FAMILYPLATES_STAGING_MAIL_ALLOWLIST" => "tester@example.net"
    }
    DESTINATIONS.each do |destination|
      names = SECRET_NAMES + (destination == "staging" ? STAGING_SECRET_NAMES : [])
      names.each do |name|
        inputs["FAMILYPLATES_#{destination.upcase}_#{name.delete_prefix('STAGING_')}"] = placeholder(destination, name)
      end
    end
    inputs
  end
end
