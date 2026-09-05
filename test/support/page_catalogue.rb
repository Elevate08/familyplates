# One list of the app's pages, used by every audit that sweeps them.
#
# Three tests each kept their own list and had already drifted apart - one
# covered 20 pages, another 19. A page added to the app should become covered by
# every audit at once, not by remembering to edit three files.
module PageCatalogue
  # Reachable by a signed-in organizer on a configured install.
  def admin_pages(recipe:, plan:, member:)
    {
      "root" => "/",
      "family members" => "/family_members",
      "preferences" => "/preferences/edit",
      "admin dashboard" => "/admin",
      "admin roster" => "/admin/family_members",
      "admin member edit" => "/admin/family_members/#{member.id}/edit",
      "admin household" => "/admin/household/edit",
      "admin calendar" => "/admin/calendar/edit",
      "pantry" => "/pantry_items",
      "recipes index" => "/recipes",
      "recipe new" => "/recipes/new",
      "recipe show" => "/recipes/#{recipe.id}",
      "recipe edit" => "/recipes/#{recipe.id}/edit",
      "recipe cook" => "/recipes/#{recipe.id}/cook",
      "recipe import" => "/recipe_imports/new",
      "meal plan" => "/meal_plans/#{plan.id}",
      "meal plan month" => "/meal_plans/#{plan.id}?view=month",
      "meal plan print" => "/meal_plans/#{plan.id}/print",
      "meal plan print month" => "/meal_plans/#{plan.id}/print?view=month",
      "grocery list" => "/grocery_list",
      "plan grocery list" => "/grocery_list/#{plan.id}"
    }
  end

  # Rendered before anyone signs in.
  def anonymous_pages
    { "profile picker" => "/select_profile" }
  end

  # Only reachable while the app has no household yet.
  def first_boot_pages
    { "onboarding family" => "/onboarding/family" }
  end

  # Routed by `resources :meal_plans` but backed by no action, so they 404.
  # Listed so a sweep does not silently skip them and call it coverage.
  UNIMPLEMENTED = %w[/meal_plans/new /meal_plans/:id/edit].freeze

  # Follows redirects so an assertion runs against what a browser would show.
  # Integration tests only - a real browser has already followed them, and the
  # NameError this used to raise there pointed at `response` rather than at the
  # actual mistake.
  def settle!(limit: 3)
    unless respond_to?(:follow_redirect!)
      raise "settle! is for integration tests; a browser follows redirects on its own"
    end

    limit.times { break unless response.redirect?; follow_redirect! }
  end
end
