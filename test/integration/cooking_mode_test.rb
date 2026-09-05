require "test_helper"

# Cook Mode is the one view meant to be used with wet hands, from across a
# counter, on whatever screen is in the kitchen. That makes three things load
# bearing that no other page cares about: it must render without the application
# chrome, it must open for a profile that is not an organizer, and it must open
# on a kiosk session - the kitchen display is the device most likely to be
# cooking from it.
class CookingModeTest < ActionDispatch::IntegrationTest
  setup do
    @household = households(:one)
    @admin = family_members(:one)
    @member = family_members(:two)

    @recipe = @household.recipes.create!(
      title: "Braised Short Ribs",
      instructions: <<~STEPS
        Sear the meat

        1. Pat the ribs dry and brown them on every side.

        2. Set them aside and sweat the onions for 8 minutes.

        Braise

        3. Return the ribs to the pot and braise for 3 hours.
      STEPS
    )
    @recipe.recipe_ingredients.create!(name: "Short ribs", quantity: 3, unit: "lbs")
    @recipe.recipe_ingredients.create!(name: "Yellow onion", quantity: 2)
  end

  test "renders every step, each with its section, and only the first one visible" do
    sign_in_as(@admin)
    get cook_recipe_url(@recipe)
    assert_response :success

    doc = Nokogiri::HTML5(response.body)
    steps = doc.css("[data-cook-mode-target='step']")

    assert_equal 3, steps.length
    assert_nil steps.first["hidden"], "the first step opens visible"
    assert_equal 2, steps.count { |step| step["hidden"] }, "later steps start hidden"

    assert_includes steps.first.text, "Pat the ribs dry"
    assert_includes steps.first.text, "Sear the meat"
    assert_includes steps.last.text, "Braise"
  end

  test "renders a countdown for each duration found in a step" do
    sign_in_as(@admin)
    get cook_recipe_url(@recipe)

    doc = Nokogiri::HTML5(response.body)
    timers = doc.css("[data-controller='step-timer']").map { |t| t["data-step-timer-seconds-value"] }

    assert_equal %w[480 10800], timers
    assert_includes response.body, "8:00"
    assert_includes response.body, "3:00:00"
  end

  test "leaves the application chrome behind" do
    sign_in_as(@admin)

    get recipe_url(@recipe)
    assert_select "nav", true, "the ordinary recipe page still has the navbar"

    get cook_recipe_url(@recipe)
    assert_select "nav", false, "cook mode renders no navigation"
    assert_select "title", /\ACook: Braised Short Ribs/
    assert_select "[data-controller='wake-lock']"
  end

  test "lists the ingredients in a drawer, each with its own checkbox" do
    sign_in_as(@admin)
    get cook_recipe_url(@recipe)

    doc = Nokogiri::HTML5(response.body)
    boxes = doc.css("[data-cook-mode-target='ingredient']")

    assert_equal 2, boxes.length
    assert_equal @recipe.recipe_ingredients.map { |ing| ing.id.to_s }.sort, boxes.map { |box| box["value"] }.sort
    assert_equal boxes.length, boxes.map { |box| box["id"] }.uniq.length, "checkbox ids must be unique"
    assert_includes response.body, "Short ribs"
    assert_not_nil doc.at_css("[data-cook-mode-target='drawer']")["hidden"], "the drawer starts closed"
  end

  test "a member who cannot edit the recipe can still cook it" do
    sign_in_as(@member)
    assert_not @member.admin?

    get cook_recipe_url(@recipe)
    assert_response :success

    # And the way in is on the page they actually look at.
    get recipe_url(@recipe)
    assert_select "a[href=?]", cook_recipe_path(@recipe)
  end

  test "a kiosk session can open cook mode even though it is barred from admin tools" do
    user = User.create!(email: "kitchen@example.com", password: "password123")
    @admin.update!(user: user)

    grant = DeviceGrant.create!(kind: "kiosk")
    grant.approve!(by: user, household: @household, kind: "kiosk")
    post token_pair_path, params: { device_code: grant.device_code }
    assert_response :success

    post set_profile_path(@admin), params: { pin: "1234" }
    assert signed_in_as?(@admin)

    get admin_root_path
    assert_redirected_to root_path, "precondition: this session really is a kiosk"

    get cook_recipe_url(@recipe)
    assert_response :success
    assert_select "[data-controller~='cook-mode']"
  end

  test "says so plainly when a recipe has no instructions, and offers no step navigation" do
    stepless = @household.recipes.create!(title: "Nothing Written Down", instructions: "")

    sign_in_as(@admin)
    get cook_recipe_url(stepless)
    assert_response :success

    assert_select "[data-cook-mode-target='step']", false
    assert_select "[data-cook-mode-target='nextButton']", false
    assert_includes response.body, "no steps written down yet"
  end

  # Recipes are addressed by a per-household number, so another household's
  # recipe reached through this path resolves to whatever this household has
  # under that number - never to theirs.
  test "another household's recipe is never cooked" do
    other = households(:two).recipes.create!(title: "Not Yours", instructions: "1. Cook.")

    sign_in_as(@admin)
    get cook_recipe_url(other)

    assert_not_includes response.body, "Not Yours"
    assert_not_includes response.body, other.id.to_s
  end
end
