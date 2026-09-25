require "test_helper"
require "open3"

# bin/coverage-criteria is only useful if it fails when a criterion has no
# test, so that is what this checks, against a throwaway tree.
class CoverageCriteriaTest < ActiveSupport::TestCase
  SCRIPT = Rails.root.join("bin/coverage-criteria").to_s

  test "passes when every criterion has a tagged Minitest or Playwright test" do
    output, status = run_against(
      criteria: { 7 => { "title" => "Card", "criteria" => { "7.1" => "One", "7.2" => "Two" } } },
      files: {
        "test/models/thing_test.rb" => "  # @card-7.1\n  test \"one\" do\n  end\n",
        "e2e/thing.spec.ts" => "test(\"two\", { tag: \"@card-7.2\" }, async () => {});\n"
      }
    )

    assert status.success?, output
    assert_includes output, "2 of 2 criteria have a tagged test."
  end

  test "fails and names each criterion without a test" do
    output, status = run_against(
      criteria: { 7 => { "title" => "Card", "criteria" => { "7.1" => "One", "7.2" => "Two" } } },
      files: { "test/models/thing_test.rb" => "  # @card-7.1\n  test \"one\" do\n  end\n" }
    )

    assert_not status.success?
    assert_match(/MISSING 7\.2/, output)
    assert_includes output, "Without a test: 7.2"
  end

  test "fails on a tag that names no criterion, so a typo is not silent" do
    output, status = run_against(
      criteria: { 7 => { "title" => "Card", "criteria" => { "7.1" => "One" } } },
      files: { "test/models/thing_test.rb" => "  # @card-7.1\n  # @card-7.9\n  test \"one\" do\n  end\n" }
    )

    assert_not status.success?
    assert_includes output, "Unknown tag @card-7.9"
  end

  test "ignores a tag outside a comment or test declaration" do
    output, status = run_against(
      criteria: { 7 => { "title" => "Card", "criteria" => { "7.1" => "One" } } },
      files: { "test/models/thing_test.rb" => "  test \"one\" do\n    assert_equal \"@card-7.1\", x\n  end\n" }
    )

    assert_not status.success?
    assert_match(/MISSING 7\.1/, output)
  end

  private

  def run_against(criteria:, files:)
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "test"))
      File.write(File.join(root, "test/acceptance_criteria.yml"), { "cards" => criteria }.to_yaml)
      files.each do |path, body|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.write(File.join(root, path), body)
      end
      Open3.capture2e({ "COVERAGE_CRITERIA_ROOT" => root }, SCRIPT)
    end
  end
end
