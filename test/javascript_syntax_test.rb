require "test_helper"
require "open3"

# `node --check` does NOT parse these files as ES modules, and silently accepted
# a controller with an orphaned object literal in its class body. The browser
# then refused to register the controller and the feature was simply dead, with
# every request test still passing - they render HTML, they do not run it.
#
# --input-type=module is the check that actually matches how the browser loads
# them through importmap.
class JavascriptSyntaxTest < ActiveSupport::TestCase
  FILES = Dir.glob(Rails.root.join("app/javascript/**/*.js")).sort.freeze

  test "every JavaScript module parses as an ES module" do
    skip "node is not available" unless node_available?

    assert_operator FILES.length, :>, 0, "precondition: there are modules to check"

    broken = FILES.filter_map do |file|
      _out, err, status = Open3.capture3("node", "--input-type=module", "--check", stdin_data: File.read(file))
      next if status.success?

      "#{file.delete_prefix(Rails.root.to_s + "/")}: #{err.lines.grep(/Error/).first&.strip}"
    end

    assert_empty broken, "these will fail to load in the browser:\n#{broken.join("\n")}"
  end

  def node_available?
    _o, _e, status = Open3.capture3("node", "--version")
    status.success?
  rescue Errno::ENOENT
    false
  end
end
