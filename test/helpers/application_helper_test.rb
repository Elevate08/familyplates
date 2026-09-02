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

  test "css_class is ignored on the emoji fallback, which is a known inconsistency" do
    # Documented, not endorsed: emoji_span hardcodes text-xl, so an emoji item
    # does not take the footprint its caller asked for and sits at a different
    # size from a hand-drawn icon next to it in the same list (grocery_lists и
    # recipes both pass w-5 h-5). Sizing the span is a visual change and wants
    # an eyeball, so this locks in today's behaviour and will fail loudly if
    # someone fixes it - at which point swap the assertion.
    markup = pantry_icon_tag("Salt", "Other", css_class: "w-9 h-9")

    assert_no_match(/w-9 h-9/, markup)
    assert_includes markup, "text-xl"
  end
end
