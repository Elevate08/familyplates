require "test_helper"

# Gemfile.saas loads the core Gemfile, and the hosted CI job boots the
# appliance bundle too, so the two lockfiles must lock every gem they share at
# the same version. Dependabot updates only Gemfile.lock; this catches the
# hosted lockfile falling behind.
class LockfileConsistencyTest < ActiveSupport::TestCase
  test "Gemfile.lock and Gemfile.saas.lock lock shared gems at the same version" do
    core = locked_versions("Gemfile.lock")
    hosted = locked_versions("Gemfile.saas.lock")

    differing = (core.keys & hosted.keys).reject { |name| core[name] == hosted[name] }.sort
    assert_empty differing, <<~MSG
      These gems are locked at different versions:
      #{differing.map { |name| "  #{name}: Gemfile.lock #{core[name]}, Gemfile.saas.lock #{hosted[name]}" }.join("\n")}
      Update the hosted lockfile to match, for example:
        BUNDLE_GEMFILE=Gemfile.saas bundle lock --update #{differing.join(" ")} --conservative
    MSG
  end

  private

  def locked_versions(file)
    Bundler::LockfileParser.new(Rails.root.join(file).read).specs.to_h { |spec| [ spec.name, spec.version.to_s ] }
  end
end
