require "test_helper"

# The CSP withholds 'unsafe-inline' from script-src, which blocks inline event
# handlers outright - they cannot be allowed by a nonce. A handler left behind
# silently stops working in the browser and no request test would notice, so the
# rendered HTML is checked directly.
class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  INLINE_HANDLER = /\son[a-z]+\s*=\s*["']/i

  setup do
    @household = households(:one)
    @admin = family_members(:one)
    @recipe = recipes(:one)
    @plan = @household.current_meal_plan
  end

  def authenticated_pages
    {
      "root" => root_path,
      "profile picker" => select_profile_path,
      "family members" => family_members_path,
      "preferences" => edit_preferences_path,
      "admin dashboard" => admin_root_path,
      "admin roster" => admin_family_members_path,
      "admin member edit" => edit_admin_family_member_path(@admin),
      "admin household" => edit_admin_household_path,
      "admin calendar" => edit_admin_calendar_path,
      "pantry" => pantry_items_path,
      "recipes index" => recipes_path,
      "recipe show" => recipe_path(@recipe),
      "recipe new" => new_recipe_path,
      "recipe edit" => edit_recipe_path(@recipe),
      "recipe import" => new_recipe_import_path,
      "meal plan" => meal_plan_path(@plan),
      "meal plan month" => meal_plan_path(@plan, view: "month"),
      "meal plan print" => print_meal_plan_path(@plan),
      "grocery list" => grocery_list_path
    }
  end

  def settle
    3.times { break unless response.redirect?; follow_redirect! }
  end

  test "no page emits an inline event handler" do
    sign_in_as(@admin)

    authenticated_pages.each do |label, path|
      get path
      settle
      assert_response :success, "#{label} did not render"

      handlers = response.body.scan(INLINE_HANDLER)
      assert_empty handlers,
        "#{label} still has #{handlers.length} inline handler(s) - the CSP will block them"
    end
  end

  test "the onboarding wizard emits no inline handlers either" do
    Household.destroy_all
    get onboarding_family_path

    assert_response :success
    assert_empty response.body.scan(INLINE_HANDLER)
  end

  test "every inline script carries the nonce" do
    sign_in_as(@admin)

    [ root_path, select_profile_path, print_meal_plan_path(@plan), edit_preferences_path ].each do |path|
      get path
      settle

      bare = response.body.scan(/<script(?![^>]*(?:nonce=|src=))[^>]*>/)
      assert_empty bare, "#{path} has an inline <script> with no nonce - the CSP will block it"
    end
  end

  test "the policy is sent and withholds unsafe-inline from scripts" do
    sign_in_as(@admin)
    get root_path
    settle

    csp = response.headers["Content-Security-Policy"]
    assert csp.present?, "no CSP header was sent"

    script_src = csp[/script-src ([^;]*)/, 1]
    assert script_src.present?
    assert_includes script_src, "'self'"
    assert_includes script_src, "'nonce-"
    assert_not_includes script_src, "unsafe-inline"
    assert_not_includes script_src, "unsafe-eval"
    assert_includes csp, "object-src 'none'"
  end

  # @card-25.1
  test "forms may post to the sign-in providers, Stripe in the hosted edition, and nowhere else" do
    sign_in_as(@admin)
    get root_path
    settle

    # form-action also governs where a submitted form is redirected, so the
    # POST to /auth/google or /subscription is blocked at the provider's door
    # unless its origin is listed.
    form_action = response.headers["Content-Security-Policy"][/form-action ([^;]*)/, 1]
    assert form_action.present?, "the policy sets no form-action"

    allowed = %w['self' https://accounts.google.com https://appleid.apple.com]
    stripe = %w[https://checkout.stripe.com https://billing.stripe.com]
    allowed += stripe if FamilyPlates.saas?
    allowed.each { |origin| assert_includes form_action.split, origin }
    assert_empty form_action.split & stripe, "an appliance has no billing, so no reason to post to Stripe" unless FamilyPlates.saas?

    # A configured OIDC provider adds its own origin; nothing else may appear.
    unless ENV["OIDC_ISSUER"].present? || ENV["OIDC_AUTH_URL"].present?
      assert_empty form_action.split - allowed
    end
  end

  test "the viewport does not block pinch-zoom" do
    sign_in_as(@admin)
    get root_path
    settle

    viewport = response.body[/<meta name="viewport"[^>]*>/]
    assert viewport.present?
    assert_not_includes viewport, "maximum-scale",
      "blocking user scaling is a WCAG 1.4.4 failure"
    assert_not_includes viewport, "user-scalable=no"
    assert_includes viewport, "viewport-fit=cover", "safe-area insets must survive"
  end
end
