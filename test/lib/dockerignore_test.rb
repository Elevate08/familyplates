require "test_helper"

# `COPY . .` in the Dockerfile sends the whole build context into the image, so
# .dockerignore is the only thing keeping git-ignored private files and
# credentials out of a locally built one (SA-06).
class DockerignoreTest < ActiveSupport::TestCase
  PRIVATE_PATHS = %w[
    tasks/security-review/notes.md
    notes/SECURITY.md
    docs/ideas/idea.md
    CONTEXT.md
    saas/DEPLOY.md
    script/hermes-review
    scratch/draft.rb
    cookies.txt
    test_output.txt
    server.log
    playwright-report/index.html
    test-results/result.json
    tmp/screenshots/failure.png
    .claude/worktrees/agent/app/models/user.rb
    .worktrees/branch/app/models/user.rb
  ].freeze

  SECRET_PATHS = %w[
    .env
    .env.production
    config/master.key
    config/credentials/production.key
    config/google_service_account.json
    config/anything.json
    config/service_account.json.key
    saas/.kamal/secrets.production
    saas/.kamal/secrets.staging
    .kamal/secrets
  ].freeze

  # Public and runtime files must still reach the image.
  KEPT_PATHS = %w[
    app/models/user.rb
    config/application.rb
    config/routes.rb
    saas/lib/familyplates_saas.rb
    saas/config/deploy.yml
    Gemfile
    Gemfile.saas
    package.json
    docs/getting-started.md
    e2e/flows/pantry.spec.ts
    log/.keep
  ].freeze

  test "private git-ignored files are kept out of the build context" do
    PRIVATE_PATHS.each { |path| assert ignored?(path), "#{path} would be copied into the image" }
  end

  test "secrets and credential files are kept out of the build context" do
    SECRET_PATHS.each { |path| assert ignored?(path), "#{path} would be copied into the image" }
  end

  test "files the image needs are not ignored" do
    KEPT_PATHS.each { |path| assert_not ignored?(path), "#{path} would be missing from the image" }
  end

  test "no tracked runtime file is ignored" do
    runtime = `git -C #{Rails.root} ls-files app lib bin db public vendor config saas/app saas/lib saas/config Gemfile Gemfile.lock Gemfile.saas Gemfile.saas.lock`.split("\n")
    runtime -= Dir.chdir(Rails.root) { Dir.glob("config/deploy*.yml") } # Kamal config, excluded on purpose
    runtime -= [ "app/assets/builds/tailwind.css" ] # rebuilt by assets:precompile in the image

    assert_not_empty runtime
    assert_empty runtime.select { |path| ignored?(path) }
  end

  private

  # Docker's rules: the last matching pattern wins, "!" re-includes, a
  # pattern that matches a directory covers everything below it, and, unlike
  # .gitignore, every pattern is anchored at the context root.
  def ignored?(path)
    parts = path.split("/")
    candidates = (1..parts.size).map { |n| parts.first(n).join("/") }

    patterns.reduce(false) do |ignored, (pattern, negated)|
      candidates.any? { |candidate| pattern.match?(candidate) } ? !negated : ignored
    end
  end

  def patterns
    @patterns ||= Rails.root.join(".dockerignore").read.lines.filter_map do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")

      negated = line.start_with?("!")
      [ Regexp.new("\\A#{glob_to_regexp(line.delete_prefix("!").delete_prefix("/"))}\\z"), negated ]
    end
  end

  def glob_to_regexp(glob)
    glob.gsub(%r{\*\*/|\*\*|\*|\?|[^*?]+}) do |token|
      case token
      when "**/" then "(?:.*/)?"
      when "**" then ".*"
      when "*" then "[^/]*"
      when "?" then "[^/]"
      else Regexp.escape(token)
      end
    end
  end
end
