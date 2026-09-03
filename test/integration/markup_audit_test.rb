require "test_helper"

# Sweeps every page for structural and accessibility defects.
#
# Written because each of these was found by hand, one page at a time, after
# passing every other check:
#
#   - a bad edit left a stray </div> and two orphaned <span>s. The ERB parsed,
#     the request returned 200, the suite stayed green, and the page was mangled.
#   - four labels per ingredient row had no `for`, so nothing associated them.
#   - the tag search box had no name at all.
#   - a label pointed at a hidden input, which cannot be labelled.
#
# All four are the same shape: correct-looking HTML that a status assertion
# cannot fault. So assert the structure directly, on every page rather than the
# one that happened to be under repair.
class MarkupAuditTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @admin = family_members(:one)
    @member = family_members(:two)
    @plan = @household.current_meal_plan
    @recipe = @household.recipes.create!(title: "Audit Subject", instructions: "Cook.")
    @recipe.recipe_ingredients.create!(name: "Chicken", unit: "lbs", quantity: 1)
    @recipe.recipe_ingredients.create!(name: "Rice", unit: "cups", quantity: 2)
  end

  def each_page
    sign_in_as(@admin)
    admin_pages(recipe: @recipe, plan: @plan, member: @admin).each do |label, path|
      get path
      settle!
      next unless response.successful?

      yield label, Nokogiri::HTML5(response.body)
    end
  end

  test "every page closes the tags it opens" do
    each_page do |label, doc|
      # Nokogiri's HTML5 parser repairs bad nesting silently, so compare the raw
      # counts - that is what catches a stray closing tag.
      body = response.body
      %w[div section form ul].each do |tag|
        opened = body.scan(/<#{tag}[\s>]/).length
        closed = body.scan("</#{tag}>").length
        assert_equal opened, closed, "#{label}: #{opened} <#{tag}> open vs #{closed} closed"
      end
      assert_empty doc.errors.select { |e| e.to_s.match?(/tag|nesting/i) }.first(3), "#{label}: parse errors"
    end
  end

  test "every label on every page is associated with a field" do
    each_page do |label, doc|
      # A hidden input has an id but cannot be labelled; treating it as a valid
      # target is what let a dangling label through an earlier version of this.
      labelable = doc.css("[id]").reject { |n| n.name == "input" && n["type"] == "hidden" }
      ids = labelable.map { |n| n["id"] }.to_set

      dangling = doc.css("label[for]").reject { |l| ids.include?(l["for"]) }
      assert_empty dangling.map { |l| l["for"] }, "#{label}: label for= points at nothing"

      orphaned = doc.css("label:not([for])").reject { |l| l.css("input,select,textarea").any? }
      assert_empty orphaned.map { |l| l.text.strip[0, 40] },
        "#{label}: label associated with nothing - use for=, wrap the input, or a <legend>"
    end
  end

  test "every form field on every page has an id or a name" do
    each_page do |label, doc|
      nameless = doc.css("input,select,textarea").reject { |f| f["id"] || f["name"] }
      assert_empty nameless.map { |f| "<#{f.name} class=#{f['class'].to_s[0, 30]}>" },
        "#{label}: form field with neither id nor name"
    end
  end

  test "no page renders the same id twice" do
    each_page do |label, doc|
      # A duplicate id silently breaks label association and getElementById,
      # which is how the PIN modal scripts find their fields.
      ids = doc.css("[id]").map { |n| n["id"] }
      duplicates = ids.tally.select { |_id, n| n > 1 }.keys
      assert_empty duplicates, "#{label}: duplicate element ids"
    end
  end

  test "every image carries alt text" do
    each_page do |label, doc|
      missing = doc.css("img").reject { |img| img["alt"] }
      assert_empty missing.map { |img| img["src"].to_s[0, 50] }, "#{label}: <img> with no alt attribute"
    end
  end

  test "the anonymous and first-boot pages hold up too" do
    anonymous_pages.each do |label, path|
      get path
      assert_response :success
      doc = Nokogiri::HTML5(response.body)
      assert_empty doc.css("input,select,textarea").reject { |f| f["id"] || f["name"] }.map { |f| f["class"].to_s[0, 30] },
        "#{label}: form field with neither id nor name"
    end

    Household.destroy_all
    first_boot_pages.each do |label, path|
      get path
      assert_response :success
      doc = Nokogiri::HTML5(response.body)
      orphaned = doc.css("label:not([for])").reject { |l| l.css("input,select,textarea").any? }
      assert_empty orphaned.map { |l| l.text.strip[0, 40] }, "#{label}: unassociated label"
    end
  end
end
