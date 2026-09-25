require "test_helper"

# Who may reach what, for every route the app has, written down in one table.
#
# The bugs this guards against have each been one controller getting its own
# check wrong, not the design: a meal slot that accepted any household's recipe
# id (4da0ea3), a finder that forgot to scope, an admin action with no
# require_admin. A test per controller only covers the checks its author
# thought to write. This one runs every route as every kind of visitor, and
# runs every record-taking route with another household's ids. The route list
# comes from config/routes.rb, so a route added without a row here fails
# "every route has a row" until someone decides who may use it.
#
# An outcome is about authorization only. :ok means the request got past the
# checks and reached the action; a 400 or 422 for a bodyless write still counts,
# because the action ran and refused the input, not the visitor.
#
# The hosted edition's routes, records and operator role are in
# saas/test/support/hosted_authorization_matrix.rb, merged in below when the
# engine is loaded.
class AuthorizationMatrixTest < ActionDispatch::IntegrationTest
  HOSTED = defined?(HostedAuthorizationMatrix) ? HostedAuthorizationMatrix : nil
  include HOSTED::TestHelpers if HOSTED

  ROLES = (%i[guest member admin] + (HOSTED ? %i[operator] : [])).freeze

  # guest:    nobody signed in
  # member:   Mom, an ordinary profile with a user account, household one
  # admin:    Dad, the household organizer, with a user account, household one
  # operator: a platform admin - a separate account with no household profile,
  #           hosted edition only
  POLICIES = {
    # Anyone, signed in or not.
    open: { guest: :ok, member: :ok, admin: :ok, operator: :ok },
    # Any profile in the household.
    household: { guest: :sign_in, member: :ok, admin: :ok, operator: :sign_in },
    # Organizer profiles only; require_admin turns ordinary members away.
    organizer: { guest: :sign_in, member: :denied, admin: :ok, operator: :sign_in },
    # The platform console, behind its own sign-in.
    operator: { guest: :operator_sign_in, member: :operator_sign_in, admin: :operator_sign_in, operator: :ok },
    # The action sends every visitor to a sign-in page, whoever they are: signing
    # out, or an OAuth return leg with no provider state.
    to_sign_in: { guest: :sign_in, member: :sign_in, admin: :sign_in, operator: :sign_in },
    # Routed by `resources` with no action behind it. If someone adds one, this
    # fails and they have to decide who may use it.
    unimplemented: { guest: :not_found, member: :not_found, admin: :not_found, operator: :not_found }
  }.freeze

  # "VERB /path" => [policy, overrides, cross_tenant]
  #
  # overrides: role => outcome where a route departs from its policy, and why.
  # cross_tenant: the outcome for household one's organizer presenting another
  # household's (or another user's) ids. nil for a route that takes none.
  MATRIX = {
    # Sessions and sign-up. Open by design: they are how a visitor gets in.
    "GET /session/new" => [ :open ],
    "POST /session" => [ :open ],
    "GET /session/verify" => [ :open ],
    "POST /session/verify" => [ :open ],
    "DELETE /session" => [ :to_sign_in ],
    "GET /signed_out" => [ :open ],

    # Profiles. The picker and set_profile are the appliance's front door.
    "GET /select_profile" => [ :open ],
    "POST /set_profile/:id" => [ :open, {}, :not_found ],
    "GET /family_members" => [ :household ],
    "POST /family_members/:id/switch" => [ :household, {}, :not_found ],
    "GET /activity" => [ :household ],

    # Account data export and deletion: organizer only.
    "GET /account_data" => [ :organizer ],
    "GET /account_data/export" => [ :organizer ],

    # Devices and passkeys belong to a user account, not a profile. A guest is
    # sent to account sign-in; the operator has no household user.
    "GET /devices" => [ :household ],
    "DELETE /devices/:id" => [ :household, {}, :not_found ],
    "DELETE /devices/destroy_all" => [ :household ],
    "GET /passkeys" => [ :household ],
    "POST /passkeys" => [ :household ],
    "DELETE /passkeys/:id" => [ :household, {}, :not_found ],
    "POST /passkeys/registration_options" => [ :household ],
    # Sign-in with a passkey, so necessarily open.
    "POST /passkeys/authentication_options" => [ :open ],
    "POST /passkeys/callback" => [ :open ],

    # External sign-in. The provider legs are open; unlinking is the user's own.
    # Providers are off in test. A profile is sent back to its preferences (where
    # it links accounts), anyone else to sign-in.
    "POST /auth/:provider" => [ :household ],
    "GET /auth/:provider/callback" => [ :to_sign_in ],
    "POST /auth/:provider/callback" => [ :to_sign_in ],
    "DELETE /auth/identities/:id" => [ :household, {}, :not_found ],

    # Device pairing. The screen being paired has no session, so the device
    # side is open; approving needs a signed-in user.
    "GET /pair" => [ :household ],
    "GET /pair/new" => [ :open ],
    "GET /kiosk" => [ :open ],
    "POST /pair/device_authorization" => [ :open ],
    "POST /pair/token" => [ :open ],
    "GET /pair/verify" => [ :household ],
    "POST /pair/approve" => [ :household ],
    "POST /pair/deny" => [ :household ],

    # Join codes and transfer links are capabilities a stranger holds.
    "GET /join" => [ :open ],
    "POST /join" => [ :open ],
    "GET /transfer/:token" => [ :open ],
    # Claiming needs an account to move the profile to.
    "POST /transfer/:token" => [ :household ],

    # The active profile's own preferences.
    "GET /preferences" => [ :household ],
    "GET /preferences/edit" => [ :household ],
    "PATCH /preferences" => [ :household ],
    "PUT /preferences" => [ :household ],

    # Household admin.
    "GET /admin" => [ :organizer ],
    "GET /admin/family_members" => [ :organizer ],
    "POST /admin/family_members" => [ :organizer ],
    "GET /admin/family_members/:id/edit" => [ :organizer, {}, :not_found ],
    "PATCH /admin/family_members/:id" => [ :organizer, {}, :not_found ],
    "PUT /admin/family_members/:id" => [ :organizer, {}, :not_found ],
    "DELETE /admin/family_members/:id" => [ :organizer, {}, :not_found ],
    "PATCH /admin/family_members/:id/reset_pin" => [ :organizer, {}, :not_found ],
    "GET /admin/household/edit" => [ :organizer ],
    "PATCH /admin/household" => [ :organizer ],
    "PUT /admin/household" => [ :organizer ],
    "POST /admin/household/reset_join_code" => [ :organizer ],
    "GET /admin/calendar" => [ :organizer ],
    "GET /admin/calendar/edit" => [ :organizer ],
    "POST /admin/calendar/regenerate_feed_token" => [ :organizer ],

    # Calendar feeds: the token is the credential, whoever presents it.
    "GET /calendars/feed/:token" => [ :open ],
    "GET /calendars/feed/:token/members/:member_id" => [ :open, {}, :not_found ],

    # First-boot wizard. family and save_family only do anything before a
    # household exists; the later steps are an organizer's.
    # On a kitchen that is already set up: a profile is sent home, anyone else
    # to the picker.
    "GET /onboarding" => [ :household ],
    "GET /setup" => [ :household ],
    "GET /onboarding/family" => [ :household ],
    "POST /onboarding/save_family" => [ :household ],
    "GET /onboarding/members" => [ :organizer ],
    "POST /onboarding/add_member" => [ :organizer ],
    "DELETE /onboarding/members/:id" => [ :organizer, {}, :not_found ],
    "GET /onboarding/recipes" => [ :organizer ],
    "POST /onboarding/save_recipes" => [ :organizer ],
    "GET /onboarding/pantry" => [ :organizer ],
    "POST /onboarding/save_pantry" => [ :organizer ],
    "GET /onboarding/complete" => [ :organizer ],

    # Pantry: any profile keeps the kitchen stocked.
    "GET /pantry_items" => [ :household ],
    "POST /pantry_items" => [ :household ],
    "PATCH /pantry_items/:id" => [ :household, {}, :not_found ],
    "PUT /pantry_items/:id" => [ :household, {}, :not_found ],
    "DELETE /pantry_items/:id" => [ :household, {}, :not_found ],
    "PATCH /pantry_items/:id/toggle_staple" => [ :household, {}, :not_found ],
    "PATCH /pantry_items/:id/toggle_low" => [ :household, {}, :not_found ],
    "PATCH /pantry_items/:id/mark_low" => [ :household, {}, :not_found ],
    "PATCH /pantry_items/:id/restock" => [ :household, {}, :not_found ],

    # Recipes: anyone in the household can read and add; changing or removing
    # one is the organizer's.
    "GET /recipes" => [ :household ],
    "GET /recipes/new" => [ :household ],
    "POST /recipes" => [ :household ],
    "GET /recipes/:id" => [ :household, {}, :not_found ],
    "GET /recipes/:id/cook" => [ :household, {}, :not_found ],
    "GET /recipes/:id/edit" => [ :organizer, {}, :not_found ],
    "PATCH /recipes/:id" => [ :organizer, {}, :not_found ],
    "PUT /recipes/:id" => [ :organizer, {}, :not_found ],
    "DELETE /recipes/:id" => [ :organizer, {}, :not_found ],
    "POST /recipes/bulk_update" => [ :organizer ],
    "POST /recipes/bulk_destroy" => [ :organizer ],
    "POST /recipes/:recipe_id/recipe_requests" => [ :household, {}, :not_found ],
    "DELETE /recipes/:recipe_id/recipe_requests/:id" => [ :household, {}, :not_found ],
    "GET /recipe_imports/new" => [ :household ],
    "POST /recipe_imports" => [ :household ],
    "GET /cook" => [ :household ],
    "POST /household_time_zone" => [ :household ],

    # Meal plans: anyone reads; slots are the organizer's. The planner at / lets
    # a visitor in only to send them to the profile picker.
    "GET /" => [ :household ],
    "GET /meal_plans" => [ :household ],
    "POST /meal_plans" => [ :unimplemented ],
    "GET /meal_plans/:id" => [ :household, {}, :not_found ],
    "GET /meal_plans/:id/print" => [ :household, {}, :not_found ],
    "GET /meal_plans/new" => [ :unimplemented ],
    "GET /meal_plans/:id/edit" => [ :unimplemented ],
    "PATCH /meal_plans/:id" => [ :unimplemented ],
    "PUT /meal_plans/:id" => [ :unimplemented ],
    "DELETE /meal_plans/:id" => [ :unimplemented ],
    "POST /meal_plans/:meal_plan_id/meal_plan_slots" => [ :organizer, {}, :not_found ],
    "PATCH /meal_plans/:meal_plan_id/meal_plan_slots/:id" => [ :organizer, {}, :not_found ],
    "PUT /meal_plans/:meal_plan_id/meal_plan_slots/:id" => [ :organizer, {}, :not_found ],
    "DELETE /meal_plans/:meal_plan_id/meal_plan_slots/:id" => [ :organizer, {}, :not_found ],
    "POST /meal_plan_slots" => [ :organizer ],
    "PATCH /meal_plan_slots/:id" => [ :organizer, {}, :not_found ],
    "PUT /meal_plan_slots/:id" => [ :organizer, {}, :not_found ],
    "DELETE /meal_plan_slots/:id" => [ :organizer, {}, :not_found ],
    "GET /grocery_list" => [ :household ],
    "GET /grocery_list/:meal_plan_id" => [ :household, {}, :not_found ]
  }.merge(HOSTED ? HOSTED::ROWS : {}).freeze

  # Routes the matrix does not drive, and why. Each is either not the app's
  # authorization to test, or is covered by a suite built for it.
  EXEMPT = {
    "GET /up" => "Health check, public by design.",
    "GET /manifest" => "PWA manifest, public by design.",
    "GET /service-worker" => "Service worker script, public by design.",
    "ANY /cable" => "Action Cable; the app defines no channels.",
    "GET /recede_historical_location" => "turbo-rails native bridge, no app data.",
    "GET /resume_historical_location" => "turbo-rails native bridge, no app data.",
    "GET /refresh_historical_location" => "turbo-rails native bridge, no app data."
  }.merge(HOSTED ? HOSTED::EXEMPT : {}).freeze

  EXEMPT_PREFIXES = {
    "/rails/" => "Framework endpoints (Active Storage, Action Mailbox and its conductor).",
    "/__test/" => "Test-only helpers, routed only in the test environment."
  }.freeze

  # Which record each path parameter names, by controller.
  PARAMS = {
    [ "profiles", "id" ] => :mom,
    [ "family_members", "id" ] => :mom,
    [ "devices", "id" ] => :device,
    [ "passkeys", "id" ] => :passkey,
    [ "external_auth", "id" ] => :identity,
    [ "external_auth", "provider" ] => :provider,
    [ "transfers", "token" ] => :transfer_token,
    [ "admin/family_members", "id" ] => :mom,
    [ "calendar_feeds", "token" ] => :calendar_token,
    [ "calendar_feeds", "member_id" ] => :mom,
    [ "onboarding", "id" ] => :mom,
    [ "pantry_items", "id" ] => :pantry_item,
    [ "recipes", "id" ] => :recipe,
    [ "recipe_requests", "recipe_id" ] => :recipe,
    [ "recipe_requests", "id" ] => :recipe_request,
    [ "meal_plans", "id" ] => :meal_plan,
    [ "meal_plan_slots", "meal_plan_id" ] => :meal_plan,
    [ "meal_plan_slots", "id" ] => :meal_plan_slot,
    [ "grocery_lists", "meal_plan_id" ] => :meal_plan
  }.merge(HOSTED ? HOSTED::PARAMS : {}).freeze

  ADMIN_DENIAL = /Access restricted|Kiosk devices cannot/

  def self.exempt_reason(key)
    EXEMPT[key] || EXEMPT_PREFIXES.find { |prefix, _| key.split(" ", 2).last.start_with?(prefix) }&.last
  end

  ROUTES = RouteInventory.all.index_by(&:key)

  test "every route has a row, and every row a route" do
    missing = ROUTES.keys.reject { |key| MATRIX.key?(key) || self.class.exempt_reason(key) }
    assert_empty missing, <<~MESSAGE
      These routes have no row in AuthorizationMatrixTest::MATRIX. Decide who may
      use each one and add it, or add it to EXEMPT with the reason it is not the
      app's authorization to test.
    MESSAGE

    stale = (MATRIX.keys + EXEMPT.keys) - ROUTES.keys
    assert_empty stale, "These rows name routes that no longer exist"
  end

  MATRIX.each do |key, (policy, overrides, cross_tenant)|
    route = ROUTES[key]
    next unless route # reported by the coverage test above

    ROLES.each do |role|
      expected = (overrides || {}).fetch(role, POLICIES.fetch(policy).fetch(role))

      test "#{role} #{key} is #{expected}" do
        sign_in_role(role)
        request_route(route, records)
        assert_outcome expected, "#{role} #{key}"
      end
    end

    next unless cross_tenant

    # @card-21.4
    test "admin #{key} with another household's ids is #{cross_tenant}" do
      sign_in_role(:admin)
      request_route(route, foreign_records)
      assert_outcome cross_tenant, "admin #{key} (foreign ids)"
    end
  end

  private

  def mom = family_members(:two)
  def dad = family_members(:one)

  def sign_in_role(role)
    case role
    when :guest
      nil
    when :member
      @user = mom_user
      sign_in_user(mom_user)
      sign_in_as(mom)
    when :admin
      @user = dad_user
      sign_in_user(dad_user)
      sign_in_as(dad)
    when :operator
      sign_in_operator
    end
  end

  def own_user = @user || dad_user
  def mom_user = @mom_user ||= user_for(mom, "mom@matrix.test")
  def dad_user = @dad_user ||= user_for(dad, "dad@matrix.test")

  def user_for(member, email)
    User.create!(email: email).tap { |user| member.update!(user: user) }
  end

  # Household one's records, which its own profiles are entitled to. Sessions,
  # passkeys and identities belong to a user, so they are the signed-in user's.
  def records
    @records ||= begin
      household = households(:one)
      {
        mom: mom.id,
        household: household.id,
        device: own_user.sessions.create!(token: SecureRandom.hex(32), kind: "browser").id,
        passkey: passkey_for(own_user).id,
        identity: own_user.identities.create!(provider: "google_oauth2", uid: "matrix-own").id,
        provider: "google_oauth2",
        transfer_token: mom.transfer_id,
        calendar_token: household.calendar_feed_token,
        pantry_item: pantry_items(:one).id,
        recipe: recipes(:one).id,
        recipe_request: recipe_requests(:one).id,
        meal_plan: meal_plans(:one).id,
        meal_plan_slot: meal_plan_slots(:one).id
      }.merge(HOSTED ? hosted_records(household) : {})
    end
  end

  # The same kinds of record, owned by household two or by a user who is not
  # the one signed in. Built here rather than in fixtures so tests that count
  # rows in household one are unaffected. The calendar token stays household
  # one's: the attack is a valid feed token naming another household's member.
  def foreign_records
    @foreign_records ||= begin
      other = households(:two)
      member = other.family_members.create!(name: "Miller Kid", role: "member", avatar_color: "#84CC16", avatar_icon: "smile")
      stranger = User.create!(email: "stranger@matrix.test")
      recipe = other.recipes.create!(title: "Miller Casserole", instructions: "Bake it.", number: 99)
      plan = meal_plans(:two)
      records.merge(
        mom: member.id,
        household: other.id,
        device: stranger.sessions.create!(token: SecureRandom.hex(32), kind: "browser").id,
        passkey: passkey_for(stranger).id,
        identity: stranger.identities.create!(provider: "google_oauth2", uid: "matrix-stranger").id,
        transfer_token: member.transfer_id,
        pantry_item: other.pantry_items.create!(name: "Miller Flour", aisle_category: "Pantry & Grains").id,
        recipe: recipe.id,
        recipe_request: recipe.recipe_requests.create!(family_member: member, week_start_date: Date.current.beginning_of_week).id,
        meal_plan: plan.id,
        meal_plan_slot: plan.meal_plan_slots.create!(date: plan.week_start_date, meal_type: "dinner", custom_title: "Miller dinner").id,
        **(HOSTED ? hosted_foreign_records(other) : {})
      )
    end
  end

  def passkey_for(user)
    user.passkeys.create!(external_id: SecureRandom.hex(16), public_key: "matrix", sign_count: 0, nickname: "Matrix key")
  end

  def request_route(route, values)
    path = route.path.gsub(/:(\w+)/) do
      name = Regexp.last_match(1)
      values.fetch(PARAMS.fetch([ route.controller, name ]) { flunk "no record for :#{name} on #{route.key}; add it to PARAMS" })
    end
    process route.verb.downcase.to_sym, path
  end

  def outcome
    location = response.location && URI(response.location).path
    if response.status == 404 then :not_found
    elsif response.status == 403 then :denied
    elsif response.status >= 500 then :error
    elsif HOSTED && operator_sign_in_redirect?(location) then :operator_sign_in
    elsif response.redirect? && flash[:alert].to_s.match?(ADMIN_DENIAL) then :denied
    elsif response.redirect? && location.in?([ select_profile_path, new_session_path ]) then :sign_in
    else :ok
    end
  end

  def assert_outcome(expected, label)
    actual = outcome
    assert_equal expected, actual,
      "#{label}: expected #{expected}, got #{actual} (#{response.status} #{response.location} #{flash.to_hash.inspect})"
  end
end
