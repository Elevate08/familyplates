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
    import = @household.recipe_imports.create!(url: "https://example.com/a")
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

  test "an unfinished import that nobody has picked up for minutes is stalled" do
    fresh = @household.recipe_imports.create!(url: "https://example.com/fresh")
    old = @household.recipe_imports.create!(url: "https://example.com/old", created_at: 10.minutes.ago)
    old_done = @household.recipe_imports.create!(url: "https://example.com/done", created_at: 10.minutes.ago, status: "succeeded")

    assert_not fresh.stalled?
    assert old.stalled?
    assert_not old_done.stalled?
    assert_equal RecipeImport::FAILURE_MESSAGES[:busy], old.failure_message
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
