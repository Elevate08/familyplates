require "test_helper"

# Both helpers build markup with raw(), and pantry_icon_tag was a stored-XSS
# sink until B-stream: the emoji column is free text the user types, and it was
# interpolated straight into the SVG string. The names these helpers switch on
# are user-controlled too - an ingredient name, a pantry item name, a member's
# avatar_icon - so the safety here rests on names only ever selecting a branch,
# never reaching the output.
class ApplicationHelperTest < ActionView::TestCase
  PAYLOAD = %q(<img src=x onerror="alert(1)">).freeze

  # --- icon_tag --------------------------------------------------------------

  test "every named icon renders a single svg" do
    names = %w[
      chef-hat calendar shopping-cart book-open printer heart heart-solid plus
      pencil edit check sparkles users trash chevron-down arrow-right archive
      link utensils star smile flame award user cog shield shield-check
      shield-outline shield-off key lock mail
    ]

    names.each do |name|
      markup = icon_tag(name)
      assert_match(/\A<svg /, markup, "#{name} should render an svg")
      assert_equal 1, markup.scan("<svg").length, "#{name} should render exactly one svg"
      assert_match(/<\/svg>\z/, markup, "#{name} should close its svg")
    end
  end

  test "an unknown icon name falls back instead of raising" do
    assert_match(/\A<svg /, icon_tag("no-such-icon"))
    assert_match(/\A<svg /, icon_tag(nil))
    assert_match(/\A<svg /, icon_tag(""))
  end

  test "an icon name never reaches the output, however hostile" do
    # This is the whole safety argument for calls like icon_tag(ing.name) and
    # icon_tag(member.avatar_icon): the name picks a branch, it is not printed.
    hostile = [ PAYLOAD, %q("><script>alert(1)</script>), "chef-hat\"><b>" ]

    hostile.each do |name|
      markup = icon_tag(name)
      assert_no_match(/script|onerror|<b>/, markup, "#{name.inspect} leaked into the markup")
    end
  end

  # --- pantry_icon_tag -------------------------------------------------------

  test "a hand-drawn icon key renders its svg" do
    %w[pepper-shaker sugar-bag oil-bottle spice-jar].each do |key|
      item = PantryItem.new(name: "Anything", emoji: key)
      assert_match(/\A<svg /, pantry_icon_tag(item), "#{key} should render its svg")
    end
  end

  test "an emoji chosen by the user is escaped, not interpolated" do
    item = PantryItem.new(name: "Salt", emoji: PAYLOAD)

    markup = pantry_icon_tag(item)

    assert_no_match(/<img/, markup, "the payload was emitted as markup - this is the stored-XSS regression")
    assert_includes markup, "&lt;img"
    assert_match(/\A<span /, markup)
  end

  test "a pantry item name is escaped when it drives the fallback" do
    item = PantryItem.new(name: PAYLOAD, emoji: nil, aisle_category: "Other")

    assert_no_match(/<img/, pantry_icon_tag(item))
  end

  test "a bare name and category work like an item" do
    assert_match(/\A<svg /, pantry_icon_tag("Black Pepper", "Spices & Baking"))
    assert_no_match(/<img/, pantry_icon_tag(PAYLOAD, "Other"))
  end

  test "a name matching a hand-drawn icon by pattern renders that svg" do
    assert_match(/aria-label="Black Pepper"/, pantry_icon_tag("cracked pepper", "Spices & Baking"))
    assert_match(/aria-label="Sugar"/, pantry_icon_tag("brown sugar", "Spices & Baking"))
    assert_match(/aria-label="Cooking Oil"/, pantry_icon_tag("canola oil", "Spices & Baking"))
  end

  test "the css_class argument lands on every svg the helpers draw" do
    assert_includes icon_tag("check", css_class: "w-3 h-3"), 'class="w-3 h-3"'
    assert_includes pantry_icon_tag("spice-jar", css_class: "w-9 h-9"), "w-9 h-9"
  end

  test "the emoji fallback takes the box it was asked for" do
    markup = pantry_icon_tag("Salt", "Other", css_class: "w-9 h-9")

    assert_includes markup, "w-9 h-9"
    assert_match(/\A<span /, markup)
  end

  test "the emoji's font size tracks its box, so it matches an svg beside it" do
    # An emoji sized only by the box would render at whatever font size it
    # inherited, which is what left the grocery list and recipe pages mixing
    # footprints. Each box gets the text size that fills it.
    {
      "w-5 h-5" => "text-base",
      "w-6 h-6" => "text-xl",
      "w-9 h-9" => "text-3xl"
    }.each do |box, text_size|
      markup = pantry_icon_tag("Salt", "Other", css_class: box)

      assert_includes markup, box
      assert_includes markup, text_size, "#{box} should carry #{text_size}"
    end
  end

  test "an unrecognised box falls back to a readable size rather than none" do
    markup = pantry_icon_tag("Salt", "Other", css_class: "size-7")

    assert_includes markup, "size-7"
    assert_includes markup, "text-xl"
  end

  test "the default size is unchanged for callers that pass no css_class" do
    # pantry_items/_pantry_item.html.erb relies on this.
    item = PantryItem.new(name: "Salt", aisle_category: "Other")

    markup = pantry_icon_tag(item)

    assert_includes markup, "w-6 h-6"
    assert_includes markup, "text-xl"
  end

  test "a user-chosen emoji is still escaped at every size" do
    item = PantryItem.new(name: "Salt", emoji: PAYLOAD)

    markup = pantry_icon_tag(item, css_class: "w-5 h-5")

    assert_no_match(/<img/, markup)
    assert_includes markup, "text-base"
  end
end
