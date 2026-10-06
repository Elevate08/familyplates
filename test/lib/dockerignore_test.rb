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

  # Git-ignored paths the image needs. None today: add one here, with the
  # reason, only if something at build or run time reads it.
  IGNORED_BUT_NEEDED = [].freeze

  test "private git-ignored files are kept out of the build context" do
    PRIVATE_PATHS.each { |path| assert ignored?(path), "#{path} would be copied into the image" }
  end

  test "secrets and credential files are kept out of the build context" do
    SECRET_PATHS.each { |path| assert ignored?(path), "#{path} would be copied into the image" }
  end

  test "deployment files are kept out of the build context" do
    DEPLOY_PATHS.each { |path| assert ignored?(path), "#{path} would be copied into the image" }
  end

  test "files the image needs are not ignored" do
    KEPT_PATHS.each { |path| assert_not ignored?(path), "#{path} would be missing from the image" }
  end

  test "no tracked runtime file is ignored" do
    runtime = git("ls-files", "app", "lib", "bin", "db", "public", "vendor", "config", "saas/app", "saas/lib", "saas/config",
                  "Gemfile", "Gemfile.lock", "Gemfile.saas", "Gemfile.saas.lock")
    runtime -= [ "app/assets/builds/tailwind.css" ] # rebuilt by assets:precompile in the image
    runtime.reject! { |path| path.match?(%r{\A(saas/)?config/deploy.*\.yml\z}) } # Kamal config, excluded on purpose

    assert_not_empty runtime
    assert_empty runtime.select { |path| ignored?(path) }
  end

  test "everything git ignores is also ignored by docker" do
    leaked = git("ls-files", "--others", "--ignored", "--exclude-standard", "--directory")
      .reject { |path| IGNORED_BUT_NEEDED.include?(path) }
      .reject { |path| ignored?(path.chomp("/")) }

    assert_empty leaked, "git-ignored but not in .dockerignore (add it, or list it in IGNORED_BUT_NEEDED with a reason)"
  end

  private

  def git(*args)
    out, status = Open3.capture2("git", "-C", Rails.root.to_s, *args)
    assert status.success?, "git #{args.first} failed"
    out.split("\n")
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
