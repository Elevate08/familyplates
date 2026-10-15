require "test_helper"
require "open3"

# `COPY . .` in the Dockerfile sends the whole build context into the image, so
# .dockerignore is the only thing keeping git-ignored private files and
# credentials out of a locally built one (SA-06).
class DockerignoreTest < ActiveSupport::TestCase
  PRIVATE_PATHS = %w[
    tasks/security-review/notes.md
    notes/SECURITY.md
    .notes/draft.md
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
    saas/.claude/settings.json
  ].freeze

  SECRET_PATHS = %w[
    .env
    .env.production
    saas/.env.production
    config/master.key
    config/credentials/production.key
    config/google_service_account.json
    config/anything.json
    config/service_account.json.key
    saas/config/master.key
    saas/config/credentials/production.key
    saas/config/service_account.json
    saas/.kamal/secrets.production
    saas/.kamal/secrets.staging
    .kamal/secrets
    db/production.sqlite3
    db/production.sqlite3-journal
    db/production.sqlite3-shm
    db/production.sqlite3-wal
    storage/production.sqlite3
  ].freeze

  # Kamal files: the image never reads them.
  DEPLOY_PATHS = %w[
    config/deploy.yml
    saas/config/deploy.yml
    saas/config/deploy.production.yml
    saas/.kamal/hooks/pre-deploy.sample
  ].freeze

  # Public and runtime files must still reach the image.
  KEPT_PATHS = %w[
    app/models/user.rb
    config/application.rb
    config/routes.rb
    config.ru
    Rakefile
    .ruby-version
    Gemfile
    Gemfile.saas
    package.json
    package-lock.json
    saas/familyplates-saas.gemspec
    saas/lib/familyplates_saas.rb
    docs/getting-started.md
    e2e/flows/pantry.spec.ts
    log/.keep
  ].freeze

  # Tracked files that .dockerignore excludes on purpose; every other tracked
  # file must reach the image.
  INTENDED_EXCLUSIONS = [
    %r{\A\.dockerignore\z},
    %r{\ADockerfile},
    %r{\A\.gitignore\z},
    %r{\A\.github/},                                  # CI
    %r{\A\.env\.example\z},                           # environment files
    %r{\A(saas/)?config/deploy.*\.yml\z},             # Kamal config
    %r{\A(saas/)?\.kamal/},                           # Kamal hooks and secrets
    %r{\Aapp/assets/builds/(?!\.keep\z)}              # rebuilt by assets:precompile in the image
  ].freeze

  test "private git-ignored files are kept out of the build context" do
    PRIVATE_PATHS.each { |path| assert ignored?(path), "#{path} would be copied into the image" }
  end

  test "secrets and credential files are kept out of the build context" do
    SECRET_PATHS.each { |path| assert ignored?(path), "#{path} would be copied into the image" }
  end

  test "host-built gems and packages are kept out of the build context" do
    %w[
      vendor/bundle/ruby/4.0.0/gems/example/lib/example.rb
      node_modules/example/index.js
      public/assets/application.css
    ].each { |path| assert ignored?(path), "#{path} would be copied into the image" }
  end

  test "deployment files are kept out of the build context" do
    DEPLOY_PATHS.each { |path| assert ignored?(path), "#{path} would be copied into the image" }
  end

  test "files the image needs are not ignored" do
    KEPT_PATHS.each { |path| assert_not ignored?(path), "#{path} would be missing from the image" }
  end

  test "no tracked file is ignored unless that is intended" do
    require_git_checkout

    tracked = git_paths("ls-files", "-z").reject { |path| INTENDED_EXCLUSIONS.any? { |pattern| pattern.match?(path) } }

    assert_not_empty tracked
    assert_empty tracked.select { |path| ignored?(path) }, "tracked files the image may need would be left out (list them in INTENDED_EXCLUSIONS if that is on purpose)"
  end

  test "everything git ignores is also ignored by docker" do
    require_git_checkout

    # Only the root .gitignore: not a developer's global excludes, and not the
    # .gitignore files inside installed gems. vendor/bundle is left out of the
    # walk; the host-built gems test above checks that docker ignores it.
    leaked = git_paths("ls-files", "-z", "--others", "--ignored", "--exclude-from=#{Rails.root.join(".gitignore")}", "--directory", "--", ".", ":(exclude)vendor/bundle")
      .map { |path| path.chomp("/") }
      .reject { |path| ignored?(path) }

    assert_empty leaked, "git-ignored but not in .dockerignore (add it, or write down why the image needs it)"
  end

  private

  # A guard that cannot run must not pass quietly: on CI it fails, locally
  # (no git, or git refuses the repository) it skips.
  def require_git_checkout
    return if git_checkout?

    flunk "needs a git checkout (CI must run the git-backed guards)" if ENV["CI"]
    skip "needs a git checkout"
  end

  def git_checkout?
    out, _err, status = Open3.capture3("git", "-C", Rails.root.to_s, "rev-parse", "--show-toplevel")
    status.success? && File.realpath(out.strip) == File.realpath(Rails.root)
  rescue SystemCallError # git is not installed
    false
  end

  # Callers pass -z: paths come back NUL-separated, so names with quotes or
  # non-ASCII characters are not escaped.
  def git_paths(*args)
    out, err, status = Open3.capture3("git", "-C", Rails.root.to_s, *args)
    assert status.success?, "git #{args.first} failed: #{err}"
    out.force_encoding(Encoding::UTF_8).split("\0")
  end

  # Docker's rules: the last matching pattern wins, "!" re-includes, a
  # pattern that matches a directory covers everything below it, and, unlike
  # .gitignore, every pattern is anchored at the context root.
  def ignored?(path)
    parts = path.split("/")
    candidates = (1..parts.size).map { |n| parts.first(n).join("/") }

    patterns.reduce(false) do |ignored, (pattern, negated)|
      candidates.any? { |candidate| File.fnmatch?(pattern, candidate, File::FNM_PATHNAME | File::FNM_DOTMATCH) } ? !negated : ignored
    end
  end

  def patterns
    @patterns ||= Rails.root.join(".dockerignore").read.lines.filter_map do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")

      negated = line.start_with?("!")
      [ line.delete_prefix("!").delete_prefix("/").chomp("/"), negated ]
    end
  end
end
