require "test_helper"

class RecipeImportTest < ActiveSupport::TestCase
  setup do
    @household = households(:one)
  end

  test "starts queued, with an unguessable id" do
    import = @household.recipe_imports.create!(url: "https://example.com/recipes/a")

    assert import.queued?
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, import.id)
  end

  test "needs a household and a url" do
    assert_not RecipeImport.new(url: "https://example.com/a").valid?
    assert_not @household.recipe_imports.new(url: "").valid?
  end

  test "refuses a status it does not know" do
    assert_not @household.recipe_imports.new(url: "https://example.com/a", status: "lost").valid?
  end

  test "scraped data comes back with symbol keys, nested ingredients included" do
    import = @household.recipe_imports.create!(url: "https://example.com/a", status: "running", started_at: Time.current)
    import.succeed!({ title: "Tacos", ingredients: [ { raw_text: "1 tortilla", quantity: 1.0 } ] })

    data = import.reload.recipe_data
    assert_equal "Tacos", data[:title]
    assert_equal 1.0, data[:ingredients].first[:quantity]
  end

  test "failure message is the ordinary one for each known error, and the generic one otherwise" do
    RecipeImport::FAILURE_MESSAGES.each do |error, message|
      import = @household.recipe_imports.create!(url: "https://example.com/#{error}", status: "failed", error: error.to_s)
      assert_equal message, import.failure_message
    end

    blocked = @household.recipe_imports.create!(url: "https://example.com/b", status: "failed", error: "blocked")
    assert_equal RecipeImport::DEFAULT_FAILURE_MESSAGE, blocked.failure_message
    assert_not RecipeImport::FAILURE_MESSAGES.key?(:blocked), "an egress refusal must look like any other bad link"
  end

  test "a queued import is stalled when nobody picked it up for a long time" do
    fresh = @household.recipe_imports.create!(url: "https://example.com/fresh")
    waiting = @household.recipe_imports.create!(url: "https://example.com/waiting", created_at: 10.minutes.ago)
    old = @household.recipe_imports.create!(url: "https://example.com/old", created_at: 40.minutes.ago)

    assert_not fresh.stalled?
    assert_not waiting.stalled?, "an import queued behind the household's other slow imports is still waiting"
    assert old.stalled?
  end

  test "a running import is stalled by how long it has run, not by how long it queued" do
    long_queued = @household.recipe_imports.create!(url: "https://example.com/a", created_at: 10.minutes.ago,
                                                    status: "running", started_at: 5.seconds.ago)
    long_running = @household.recipe_imports.create!(url: "https://example.com/b", status: "running", started_at: 10.minutes.ago)

    assert_not long_queued.stalled?
    assert long_running.stalled?
  end

  test "a finished import is never stalled" do
    done = @household.recipe_imports.create!(url: "https://example.com/done", created_at: 10.minutes.ago, status: "succeeded")
    failed = @household.recipe_imports.create!(url: "https://example.com/failed", created_at: 10.minutes.ago, status: "failed")

    assert_not done.stalled?
    assert_not failed.stalled?
  end

  test "stall! fails an unfinished import with the busy message and leaves a finished one alone" do
    old = @household.recipe_imports.create!(url: "https://example.com/old", created_at: 40.minutes.ago)
    done = @household.recipe_imports.create!(url: "https://example.com/done", status: "succeeded")

    old.stall!
    done.stall!

    assert old.failed?
    assert_equal "busy", old.error
    assert_equal RecipeImport::FAILURE_MESSAGES[:busy], old.failure_message
    assert old.finished_at
    assert done.succeeded?
  end

  test "claim! lets exactly one caller start a queued import" do
    import = @household.recipe_imports.create!(url: "https://example.com/a")
    same = RecipeImport.find(import.id)

    assert import.claim!
    assert import.running?
    assert import.started_at
    assert_not same.claim!, "a second worker must not start the same import"
    assert_not same.reload.queued?
  end

  test "claim! refuses an import that was failed as stalled while it waited" do
    import = @household.recipe_imports.create!(url: "https://example.com/a", created_at: 40.minutes.ago)
    RecipeImport.find(import.id).stall!

    assert_not import.claim!
    assert import.reload.failed?
  end

  test "the saved recipe and the succeeded import are written together" do
    import = @household.recipe_imports.create!(url: "https://example.com/a")
    import.claim!
    import.define_singleton_method(:finish_running!) { |*| raise ActiveRecord::StatementInvalid, "disk full" }

    assert_no_difference "Recipe.count" do
      assert_raises(ActiveRecord::StatementInvalid) { import.succeed!({ title: "Half Done", servings: 4 }) }
    end
  end

  test "a failed aisle resync is logged, and the saved recipe is still reported as imported" do
    import = @household.recipe_imports.create!(url: "https://example.com/a", status: "running", started_at: Time.current)
    log = StringIO.new
    original_logger = Rails.logger
    original = Recipe.instance_method(:resync_aisle_mappings!)
    Rails.logger = Logger.new(log)
    Recipe.define_method(:resync_aisle_mappings!) { raise "aisle trouble" }

    assert_difference "Recipe.count", 1 do
      import.succeed!({ title: "Tacos", servings: 4 })
    end

    assert import.reload.succeeded?
    assert_equal Recipe.order(:id).last.id, import.recipe_id
    assert_match(/aisle resync failed/, log.string)
  ensure
    Recipe.define_method(:resync_aisle_mappings!, original)
    Rails.logger = original_logger
  end

  test "stall! only fails the status the caller saw, so a job that has started is not failed" do
    import = @household.recipe_imports.create!(url: "https://example.com/a", created_at: 40.minutes.ago)
    seen_queued = RecipeImport.find(import.id)
    assert seen_queued.stalled?

    assert import.claim!
    seen_queued.stall!

    assert seen_queued.running?
    assert import.reload.running?
    assert_nil import.error
  end

  test "succeed! saves nothing when the import is no longer running" do
    import = @household.recipe_imports.create!(url: "https://example.com/a", created_at: 40.minutes.ago)
    assert import.claim!
    RecipeImport.find(import.id).stall!

    assert_no_difference "Recipe.count" do
      assert_not import.succeed!({ title: "Too Late", servings: 4 })
    end

    import.reload
    assert import.failed?
    assert_equal "busy", import.error
    assert_nil import.recipe_id
  end

  test "fail! does not overwrite an import that is no longer running" do
    import = @household.recipe_imports.create!(url: "https://example.com/a")
    assert import.claim!
    assert import.succeed!({ title: "Done First", servings: 4 })

    assert_not import.fail!(:timeout)

    assert import.reload.succeeded?
    assert_nil import.error
  end

  test "succeed! and fail! on a deleted import do nothing and do not raise" do
    import = @household.recipe_imports.create!(url: "https://example.com/a")
    assert import.claim!
    RecipeImport.where(id: import.id).delete_all

    assert_no_difference "Recipe.count" do
      assert_not import.succeed!({ title: "Orphan", servings: 4 })
    end
    assert_not import.fail!(:timeout)
  end

  test "old imports expire" do
    keep = @household.recipe_imports.create!(url: "https://example.com/keep")
    drop = @household.recipe_imports.create!(url: "https://example.com/drop", created_at: 2.days.ago)

    assert_equal [ drop ], RecipeImport.expired.to_a
    assert_not_includes RecipeImport.expired, keep
  end

  test "goes with its household, and outlives the person who asked" do
    member = @household.family_members.create!(name: "Temp", role: "member", avatar_color: "#84CC16", avatar_icon: "smile")
    import = @household.recipe_imports.create!(url: "https://example.com/a", family_member: member)

    member.destroy!
    assert_nil import.reload.family_member_id

    other = households(:two)
    theirs = other.recipe_imports.create!(url: "https://example.com/b")
    other.destroy!
    assert_not RecipeImport.exists?(theirs.id)
  end
end
