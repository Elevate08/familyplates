require "test_helper"
require "open3"

# The appliance and the hosted service are two bundles of one app. These
# check the switch between them, which happens before Rails loads.
class EditionsTest < ActiveSupport::TestCase
  test "boot selects the hosted bundle only for hosted mode" do
    assert_equal "Gemfile", selected_gemfile({})
    assert_equal "Gemfile", selected_gemfile("FAMILYPLATES_MODE" => "appliance")
    assert_equal "Gemfile.saas", selected_gemfile("FAMILYPLATES_MODE" => "hosted")
    assert_equal "Gemfile.saas", selected_gemfile("APP_MODE" => "hosted")
  end

  test "an explicit BUNDLE_GEMFILE wins over the mode" do
    assert_equal "Gemfile", selected_gemfile("FAMILYPLATES_MODE" => "hosted", "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s)
  end

  test "saas? says whether the hosted engine is loaded" do
    assert_equal defined?(FamilyPlatesSaas::Engine).present?, FamilyPlates.saas?
  end

  test "hosted mode without the hosted engine is refused" do
    original = FamilyPlates.method(:saas?)
    FamilyPlates.define_singleton_method(:saas?) { false }

    error = assert_raises(FamilyPlates::HostedEditionMissingError) { FamilyPlates.require_hosted_edition! }
    assert_match "FAMILYPLATES_MODE=hosted", error.message
  ensure
    FamilyPlates.define_singleton_method(:saas?, original)
  end

  test "an appliance bundle will not boot in hosted mode" do
    _out, err, status = Bundler.with_unbundled_env { Open3.capture3(
      { "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s, "FAMILYPLATES_MODE" => "hosted", "RAILS_ENV" => "test" },
      Rails.root.join("bin/rails").to_s, "runner", "puts :booted", chdir: Rails.root.to_s
    ) }

    assert_not status.success?
    assert_match "HostedEditionMissingError", err
  end

  private

  def selected_gemfile(env)
    clean = { "BUNDLE_GEMFILE" => nil, "FAMILYPLATES_MODE" => nil, "APP_MODE" => nil }.merge(env)
    script = "load #{Rails.root.join('config/boot.rb').to_s.dump} rescue nil; print File.basename(ENV['BUNDLE_GEMFILE'])"
    # Unbundled, or the parent's bundler/setup in RUBYOPT picks the Gemfile first.
    Bundler.with_unbundled_env { Open3.capture3(clean, RbConfig.ruby, "-e", script, chdir: Rails.root.to_s) }.first
  end
end
