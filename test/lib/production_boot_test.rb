require "test_helper"
require "open3"

# Nothing else boots the production environment: every other test runs in
# test, and release/v1.3.0 shipped an initializer that could not load in
# production (FamilyPlates was not yet autoloadable). These boot it for real.
class ProductionBootTest < ActiveSupport::TestCase
  test "an appliance boots in production with no deployment settings" do
    out, err, status = boot_production("FAMILYPLATES_MODE" => "appliance")

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

  private

  def boot_production(env)
    clean = { "RAILS_ENV" => "production", "APP_HOST" => nil, "SMTP_ADDRESS" => nil, "SECRET_KEY_BASE_DUMMY" => "1",
              "BUNDLE_GEMFILE" => ENV["BUNDLE_GEMFILE"] }.merge(env)
    clean["SECRET_KEY_BASE_DUMMY"] = nil unless env.key?("SECRET_KEY_BASE_DUMMY")
    clean["SECRET_KEY_BASE"] = "x" * 64 if clean["SECRET_KEY_BASE_DUMMY"].nil?
    Bundler.with_unbundled_env do
      Open3.capture3(clean, Rails.root.join("bin/rails").to_s, "runner", "puts :booted", chdir: Rails.root.to_s)
    end
  end
end
