require "test_helper"
require "tmpdir"

load Rails.root.join("bin/wiki-sync").to_s

class WikiSyncTest < ActiveSupport::TestCase
  setup do
    @root = Pathname(Dir.mktmpdir)
    @docs = @root.join("docs").tap(&:mkpath)
    @wiki = @root.join("wiki").tap(&:mkpath)
    @wiki.join(".git").mkpath
    @root.join("LICENSE.md").write("license")
  end

  teardown { FileUtils.rm_rf(@root) }

  test "flattens docs into pages and rewrites links to page names" do
    write "Home.md", "[Deploy](hosted/deploying.md#first-deploy) and [Sidebar style](getting-started)"
    write "getting-started.md", "Back [home](./Home.md)"
    write "hosted/deploying.md", "See [editions](../getting-started.md) and [the license](../../LICENSE.md)"

    assert_equal %w[Home deploying getting-started], sync.sort
    assert_equal "[Deploy](deploying#first-deploy) and [Sidebar style](getting-started)", page("Home")
    assert_equal "See [editions](getting-started) and [the license](https://example.test/blob/master/LICENSE.md)", page("deploying")
  end

  test "leaves the planning notes in docs/ideas out, and links to them go to GitHub" do
    write "Home.md", "[the plan](ideas/tenancy.md)"
    write "ideas/tenancy.md", "notes"

    assert_equal %w[Home], sync
    assert_equal "[the plan](https://example.test/blob/master/docs/ideas/tenancy.md)", page("Home")
  end

  test "leaves URLs and anchors alone" do
    write "Home.md", "[site](https://example.com/a.md) [top](#top) [mail](mailto:a@b.c)"

    sync
    assert_equal "[site](https://example.com/a.md) [top](#top) [mail](mailto:a@b.c)", page("Home")
  end

  test "removes wiki pages that are no longer in docs, but not the git checkout" do
    write "Home.md", "hello"
    @wiki.join("google-calendar-integration.md").write("stale")
    @wiki.join("ideas").mkpath
    @wiki.join("ideas/old.md").write("stale")

    sync

    assert_equal [ "Home.md" ], @wiki.glob("**/*.md").map { |p| p.relative_path_from(@wiki).to_s }
    assert @wiki.join(".git").directory?
    assert_not @wiki.join("ideas").exist?
  end

  test "a link to a missing file stops the sync before anything is written" do
    write "Home.md", "[gone](missing.md)"
    @wiki.join("existing.md").write("keep")

    error = assert_raises(WikiSync::Error) { sync }
    assert_match "docs/Home.md links to missing.md, which does not exist", error.message
    assert @wiki.join("existing.md").exist?
  end

  test "two docs with the same name are refused" do
    write "deploying.md", "a"
    write "hosted/deploying.md", "b"

    error = assert_raises(WikiSync::Error) { sync }
    assert_match "Two docs would be the wiki page deploying", error.message
  end

  test "the real docs sync without a broken link" do
    Dir.mktmpdir do |wiki|
      Dir.mkdir(File.join(wiki, ".git"))
      pages = WikiSync.new(docs: Rails.root.join("docs"), wiki: wiki, root: Rails.root).run
      assert_includes pages, "editions"
    end
  end

  private

  def write(path, text)
    @docs.join(path).tap { |p| p.dirname.mkpath }.write(text)
  end

  def sync
    WikiSync.new(docs: @docs, wiki: @wiki, root: @root, repo_url: "https://example.test/blob/master").run
  end

  def page(name)
    @wiki.join("#{name}.md").read
  end
end
