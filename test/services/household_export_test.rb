require "test_helper"

class HouseholdExportTest < ActiveSupport::TestCase
  TOP_LEVEL_KEYS = %i[export_version exported_at household family_members recipes pantry_items meal_plans].freeze
  HOUSEHOLD_KEYS = %w[id name created_at onboarded_at].freeze
  MEMBER_KEYS = %w[id name role avatar_color avatar_icon created_at email].freeze
  RECIPE_KEYS = %w[id number title description instructions tags meal_types created_at ingredients].freeze
  INGREDIENT_KEYS = %w[name quantity unit raw_text].freeze
  PANTRY_KEYS = %w[id name aisle_category is_staple emoji created_at].freeze
  PLAN_KEYS = %w[id number week_start_date created_at slots].freeze
  SLOT_KEYS = %w[id date meal_type custom_title is_leftover created_at recipe_id].freeze

  FOREIGN_MARKER = "Foreign Marker".freeze

  setup do
    @household = households(:one)
    @other = households(:two)
    @base_time = Time.utc(2025, 1, 1, 12, 0, 0)
  end

  test "exports exactly the top-level keys with version 1 and the frozen time" do
    export = travel_to(Time.utc(2026, 3, 4, 5, 6, 7)) { HouseholdExport.call(@household) }

    assert_equal TOP_LEVEL_KEYS, export.keys
    assert_equal 1, export[:export_version]
    assert_equal "2026-03-04T05:06:07Z", export[:exported_at]
  end

  test "exports the household's own fields and nothing else" do
    export = HouseholdExport.call(@household)

    assert_equal(
      {
        "id" => @household.id,
        "name" => "Spencer Family",
        "created_at" => @household.created_at,
        "onboarded_at" => @household.onboarded_at
      },
      export[:household]
    )
    assert_not_nil export[:household]["onboarded_at"]
    %w[join_code calendar_feed_token promotion_code suspended_at time_zone].each do |field|
      assert_not export[:household].key?(field), "household export leaked #{field}"
    end
  end

  test "exports member values with the linked user's email and nil for unlinked members" do
    user = User.create!(email: "linked.parent@example.test", password: "correct-horse-battery")
    linked = @household.family_members.create!(name: "Linked Parent", role: "member", avatar_color: "#10B981", avatar_icon: "star", user: user)

    members = HouseholdExport.call(@household)[:family_members]
    by_id = members.index_by { |member| member["id"] }

    assert_equal [ family_members(:one).id, family_members(:two).id, linked.id ].sort, by_id.keys.sort
    members.each { |member| assert_equal MEMBER_KEYS, member.keys }

    dad = family_members(:one)
    assert_equal(
      {
        "id" => dad.id,
        "name" => "Dad",
        "role" => "admin",
        "avatar_color" => "#3B82F6",
        "avatar_icon" => "chef-hat",
        "created_at" => dad.created_at,
        "email" => nil
      },
      by_id[dad.id]
    )
    assert_nil by_id[family_members(:two).id]["email"]

    assert_equal(
      {
        "id" => linked.id,
        "name" => "Linked Parent",
        "role" => "member",
        "avatar_color" => "#10B981",
        "avatar_icon" => "star",
        "created_at" => linked.created_at,
        "email" => "linked.parent@example.test"
      },
      by_id[linked.id]
    )
  end

  test "never exports authentication fields for members or users" do
    user = User.create!(email: "secret.keeper@example.test", password: "correct-horse-battery")
    @household.family_members.create!(name: "Secret Keeper", role: "member", user: user)
    dad = family_members(:one)
    assert dad.pin_digest.present?
    assert user.password_digest.present?

    export = HouseholdExport.call(@household)

    export[:family_members].each do |member|
      %w[pin_digest password_digest user_id household_id updated_at].each do |field|
        assert_not member.key?(field), "member export leaked #{field}"
      end
    end
    json = export.to_json
    assert_not_includes json, dad.pin_digest
    assert_not_includes json, user.password_digest
    assert_not_includes json, user.id
  end

  test "exports recipe values and their ingredients through the field allowlists" do
    recipe = recipes(:one)

    recipes_export = HouseholdExport.call(@household)[:recipes]
    recipes_export.each do |exported|
      assert_equal RECIPE_KEYS, exported.keys
      exported["ingredients"].each { |ingredient| assert_equal INGREDIENT_KEYS, ingredient.keys }
    end

    exported = recipes_export.find { |candidate| candidate["id"] == recipe.id }
    assert_not_nil exported
    assert_equal(
      {
        "id" => recipe.id,
        "number" => 1,
        "title" => "Taco Tuesday",
        "description" => "Delicious beef tacos",
        "instructions" => "Cook meat, warm shells, assemble.",
        "tags" => "Quick, Mexican",
        "meal_types" => "breakfast,lunch,dinner",
        "created_at" => recipe.created_at
      },
      exported.except("ingredients")
    )

    # The ingredient relation has no explicit order, so compare order-independently.
    assert_equal(
      [
        { "name" => "Ground Beef", "quantity" => BigDecimal("1"), "unit" => "lb", "raw_text" => "1 lb ground beef" },
        { "name" => "Taco Shells", "quantity" => BigDecimal("12"), "unit" => "count", "raw_text" => "12 taco shells" }
      ],
      exported["ingredients"].sort_by { |ingredient| ingredient["name"] }
    )

    spaghetti = recipes_export.find { |candidate| candidate["id"] == recipes(:two).id }
    assert_equal [], spaghetti["ingredients"]
  end

  test "exports pantry item values through the field allowlist" do
    salt = @household.pantry_items.create!(name: "Sea Salt", aisle_category: "Spices & Baking", is_staple: false, emoji: "🧂", low_stock_at: Time.current)

    pantry = HouseholdExport.call(@household)[:pantry_items]
    pantry.each { |item| assert_equal PANTRY_KEYS, item.keys }
    by_id = pantry.index_by { |item| item["id"] }

    assert_equal [ pantry_items(:one).id, pantry_items(:two).id, salt.id ].sort, by_id.keys.sort
    assert_equal(
      { "id" => salt.id, "name" => "Sea Salt", "aisle_category" => "Spices & Baking", "is_staple" => false, "emoji" => "🧂", "created_at" => salt.created_at },
      by_id[salt.id]
    )
    olive_oil = pantry_items(:one)
    assert_equal(
      { "id" => olive_oil.id, "name" => "Olive Oil", "aisle_category" => "Pantry & Grains", "is_staple" => true, "emoji" => nil, "created_at" => olive_oil.created_at },
      by_id[olive_oil.id]
    )
  end

  test "exports meal plans and slots through the field allowlists" do
    plan = meal_plans(:one)
    picnic = plan.meal_plan_slots.create!(date: plan.week_start_date + 2.days, meal_type: "lunch", custom_title: "Picnic", notes: "Private note", family_member: family_members(:two))

    plans = HouseholdExport.call(@household)[:meal_plans]
    assert_equal [ plan.id ], plans.map { |exported| exported["id"] }

    exported_plan = plans.first
    assert_equal PLAN_KEYS, exported_plan.keys
    assert_equal(
      { "id" => plan.id, "number" => 1, "week_start_date" => plan.week_start_date, "created_at" => plan.created_at },
      exported_plan.except("slots")
    )

    exported_plan["slots"].each { |slot| assert_equal SLOT_KEYS, slot.keys }
    by_id = exported_plan["slots"].index_by { |slot| slot["id"] }
    assert_equal [ meal_plan_slots(:one).id, meal_plan_slots(:two).id, picnic.id ].sort, by_id.keys.sort

    assert_equal(
      { "id" => picnic.id, "date" => plan.week_start_date + 2.days, "meal_type" => "lunch", "custom_title" => "Picnic", "is_leftover" => false, "created_at" => picnic.created_at, "recipe_id" => nil },
      by_id[picnic.id]
    )
    taco_night = meal_plan_slots(:one)
    assert_equal(
      { "id" => taco_night.id, "date" => plan.week_start_date, "meal_type" => "dinner", "custom_title" => taco_night.custom_title, "is_leftover" => false, "created_at" => taco_night.created_at, "recipe_id" => recipes(:one).id },
      by_id[taco_night.id]
    )
    assert_not_includes exported_plan.to_json, "Private note"
  end

  test "sorts members by created_at then id, including ties" do
    records = [ family_members(:one), family_members(:two) ] +
      %w[Alpha Bravo Charlie].map { |name| @household.family_members.create!(name: name) }
    stamp(records, [ 2.hours, 0, 1.hour, 1.hour, 0 ])

    assert_sorted_with_ties records, HouseholdExport.call(@household)[:family_members]
  end

  test "sorts recipes by created_at then id, including ties" do
    records = [ recipes(:one), recipes(:two) ] +
      [ "Alpha Soup", "Bravo Salad", "Charlie Curry" ].map { |title| @household.recipes.create!(title: title) }
    stamp(records, [ 3.hours, 1.hour, 3.hours, 0, 1.hour ])

    assert_sorted_with_ties records, HouseholdExport.call(@household)[:recipes]
  end

  test "sorts pantry items by created_at then id, including ties" do
    records = [ pantry_items(:one), pantry_items(:two) ] +
      %w[Flour Sugar Rice].map { |name| @household.pantry_items.create!(name: name, aisle_category: "Pantry & Grains") }
    stamp(records, [ 1.hour, 1.hour, 0, 2.hours, 0 ])

    assert_sorted_with_ties records, HouseholdExport.call(@household)[:pantry_items]
  end

  test "sorts meal plans by week_start_date and slots by date then meal_type" do
    current = meal_plans(:one)
    later = @household.meal_plans.create!(week_start_date: current.week_start_date + 1.week)
    earlier = @household.meal_plans.create!(week_start_date: current.week_start_date - 1.week)

    monday = current.week_start_date
    lunch = current.meal_plan_slots.create!(date: monday, meal_type: "lunch", custom_title: "Sandwiches")
    breakfast = current.meal_plan_slots.create!(date: monday, meal_type: "breakfast", recipe: recipes(:two))
    later_dinner = later.meal_plan_slots.create!(date: later.week_start_date + 3.days, meal_type: "dinner", custom_title: "Later dinner")
    later_breakfast = later.meal_plan_slots.create!(date: later.week_start_date, meal_type: "breakfast", custom_title: "Later breakfast")

    plans = HouseholdExport.call(@household)[:meal_plans]
    assert_equal [ earlier.id, current.id, later.id ], plans.map { |plan| plan["id"] }

    current_slots = [ meal_plan_slots(:one), meal_plan_slots(:two), lunch, breakfast ]
    expected_current = current_slots.sort_by { |slot| [ slot.date, slot.meal_type ] }.map(&:id)
    # meal_type sorts as a string, so Monday reads breakfast, dinner, lunch.
    assert_equal [ breakfast.id, meal_plan_slots(:one).id, lunch.id, meal_plan_slots(:two).id ], expected_current
    assert_equal expected_current, plans[1]["slots"].map { |slot| slot["id"] }

    assert_equal [ later_breakfast.id, later_dinner.id ], plans[2]["slots"].map { |slot| slot["id"] }
    assert_equal [], plans[0]["slots"]
  end

  test "exports only the household's own records in every collection" do
    foreign = create_foreign_records

    export = HouseholdExport.call(@household)

    assert_equal @household.id, export[:household]["id"]
    assert_not_equal @other.id, export[:household]["id"]

    member_ids = export[:family_members].map { |member| member["id"] }
    assert_equal [ family_members(:one).id, family_members(:two).id ].sort, member_ids.sort
    assert_not_includes member_ids, foreign[:member].id
    assert_not_includes export[:family_members].map { |member| member["email"] }, foreign[:user].email

    recipe_ids = export[:recipes].map { |recipe| recipe["id"] }
    assert_equal [ recipes(:one).id, recipes(:two).id ].sort, recipe_ids.sort
    assert_not_includes recipe_ids, foreign[:recipe].id

    ingredient_names = export[:recipes].flat_map { |recipe| recipe["ingredients"].map { |ingredient| ingredient["name"] } }
    assert_equal [ "Ground Beef", "Taco Shells" ], ingredient_names.sort
    assert_not_includes ingredient_names, foreign[:ingredient].name

    pantry_ids = export[:pantry_items].map { |item| item["id"] }
    assert_equal [ pantry_items(:one).id, pantry_items(:two).id ].sort, pantry_ids.sort
    assert_not_includes pantry_ids, foreign[:pantry_item].id

    plan_ids = export[:meal_plans].map { |plan| plan["id"] }
    assert_equal [ meal_plans(:one).id ], plan_ids
    assert_not_includes plan_ids, meal_plans(:two).id

    slots = export[:meal_plans].flat_map { |plan| plan["slots"] }
    assert_equal [ meal_plan_slots(:one).id, meal_plan_slots(:two).id ].sort, slots.map { |slot| slot["id"] }.sort
    assert_not_includes slots.map { |slot| slot["id"] }, foreign[:slot].id
    assert_not_includes slots.map { |slot| slot["recipe_id"] }, foreign[:recipe].id

    assert_not_includes export.to_json, FOREIGN_MARKER
    assert_not_includes export.to_json, foreign[:user].email
  end

  test "exports the other household's records without any of this household's" do
    foreign = create_foreign_records

    export = HouseholdExport.call(@other)

    assert_equal @other.id, export[:household]["id"]
    assert_equal [ foreign[:member].id ], export[:family_members].map { |member| member["id"] }
    assert_equal foreign[:user].email, export[:family_members].first["email"]
    assert_equal [ foreign[:recipe].id ], export[:recipes].map { |recipe| recipe["id"] }
    assert_equal [ foreign[:ingredient].name ], export[:recipes].first["ingredients"].map { |ingredient| ingredient["name"] }
    assert_equal [ foreign[:pantry_item].id ], export[:pantry_items].map { |item| item["id"] }
    assert_equal [ meal_plans(:two).id ], export[:meal_plans].map { |plan| plan["id"] }
    assert_equal [ foreign[:slot].id ], export[:meal_plans].first["slots"].map { |slot| slot["id"] }

    json = export.to_json
    [ recipes(:one).title, recipes(:two).title, pantry_items(:one).name, pantry_items(:two).name, "Ground Beef", "Taco Shells", family_members(:one).name ].each do |own_marker|
      assert_not_includes json, own_marker
    end
  end

  private

  # Offsets from @base_time, applied in record order so timestamps are neither
  # insertion-ordered nor unique.
  def stamp(records, offsets)
    records.zip(offsets).each { |record, offset| record.update_columns(created_at: @base_time + offset) }
  end

  def assert_sorted_with_ties(records, exported)
    assert records.group_by(&:created_at).values.any? { |group| group.size > 1 }, "fixture setup must include a created_at tie"
    assert_not_equal records.map(&:created_at), records.map(&:created_at).sort, "fixture setup must not be insertion-ordered"

    expected = records.sort_by { |record| [ record.created_at, record.id ] }.map(&:id)
    assert_equal expected, exported.map { |row| row["id"] }
  end

  def create_foreign_records
    user = User.create!(email: "foreign.marker@example.test", password: "correct-horse-battery")
    member = @other.family_members.create!(name: "#{FOREIGN_MARKER} Cook", role: "member", user: user)
    recipe = @other.recipes.create!(title: "#{FOREIGN_MARKER} Stew", description: "#{FOREIGN_MARKER} description", tags: FOREIGN_MARKER)
    ingredient = recipe.recipe_ingredients.create!(name: "#{FOREIGN_MARKER} Saffron", raw_text: "1 pinch #{FOREIGN_MARKER} Saffron", quantity: 1, unit: "pinch", aisle_category: "Spices & Baking")
    pantry_item = @other.pantry_items.create!(name: "#{FOREIGN_MARKER} Spice", aisle_category: "Spices & Baking")
    plan = meal_plans(:two)
    slot = plan.meal_plan_slots.create!(date: plan.week_start_date + 4.days, meal_type: "dinner", recipe: recipe, custom_title: "#{FOREIGN_MARKER} Feast")

    { user: user, member: member, recipe: recipe, ingredient: ingredient, pantry_item: pantry_item, slot: slot }
  end
end
