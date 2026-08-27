# Task Breakdown: MealHub - 5-Minute Family Meal Planner

## Phase 1: Project Setup, Data Foundations & Native Auth

### Task 1: Rails 8 App Initialization & Tailwind / Hotwire Setup
**Description:** Generate the Rails 8 application skeleton configured with SQLite, Tailwind CSS, Hotwire (Turbo + Stimulus), and setup the test framework.

**Acceptance criteria:**
- [x] Rails 8 app boots successfully with SQLite.
- [x] Tailwind CSS compiles and is configured with custom color palette and typography.
- [x] Root route displays a landing/welcome page with working Turbo Drive.

**Verification:**
- [x] Tests pass: `bin/rails test`
- [x] Build succeeds: `bin/rails assets:precompile`
- [x] Manual check: Navigate to `http://localhost:3000` and confirm styled Tailwind welcome page.

**Dependencies:** None
**Files likely touched:**
- `Gemfile`
- `config/routes.rb`
- `app/views/layouts/application.html.erb`
- `app/controllers/home_controller.rb`
**Estimated scope:** Medium (3-5 files)

---

### Task 2: Household & Rails 8 Native Authentication
**Description:** Implement `Household`, `User`, and `Session` models using Rails 8 native auth generator (`has_secure_password`), supporting user signup, signin, signout, and password resets.

**Acceptance criteria:**
- [x] Household model created; each User belongs to a Household.
- [x] Rails 8 native authentication controllers and views styled cleanly with Tailwind.
- [x] Authenticated users can log in, view account settings, and log out with persistent session cookie.

**Verification:**
- [x] Tests pass: `bin/rails test test/models/user_test.rb test/controllers/sessions_controller_test.rb`
- [x] Manual check: Register a new household account, log out, log back in.

**Dependencies:** Task 1
**Files likely touched:**
- `app/models/household.rb`
- `app/models/user.rb`
- `app/models/session.rb`
- `app/controllers/sessions_controller.rb`
- `app/controllers/registrations_controller.rb`
- `app/views/sessions/new.html.erb`
- `app/views/registrations/new.html.erb`
**Estimated scope:** Medium (4-5 files)

---

### Task 3: Family Member Profiles & Active Member Switcher
**Description:** Implement `FamilyMember` model (name, avatar_color, role) and a 1-tap top navigation profile switcher that stores the active member in session/signed cookie (`Current.family_member`).

**Acceptance criteria:**
- [x] `Household` has many `FamilyMember` records.
- [x] Top bar displays current active family member avatar with dropdown to switch member in 1 tap.
- [x] `Current.family_member` and `Current.household` are automatically populated in `ApplicationController`.

**Verification:**
- [x] Tests pass: `bin/rails test test/models/family_member_test.rb test/controllers/family_members_controller_test.rb`
- [x] Manual check: Create family members (e.g. "Dad", "Mom", "Kids"), switch between them, verify badge updates via Turbo Frame.

**Dependencies:** Task 2
**Files likely touched:**
- `app/models/family_member.rb`
- `app/controllers/family_members_controller.rb`
- `app/controllers/concerns/authentication.rb`
- `app/views/shared/_navbar.html.erb`
- `app/views/family_members/_switcher.html.erb`
**Estimated scope:** Medium (4-5 files)

---

## Checkpoint: Foundation
- [x] All tests pass: `bin/rails test`
- [x] Account owner can sign up, create household members, and switch active profile seamlessly.

---

## Phase 2: Onboarding Wizard & Starter Pack

### Task 4: Pantry Items & Default Pantry Staples Setup
**Description:** Create `PantryItem` model (name, aisle_category, is_staple) and provide a manageable pantry settings view with pre-seeded staple defaults.

**Acceptance criteria:**
- [x] `PantryItem` model associated with `Household`.
- [x] Standard list of 15+ pantry staples available for initial seeding (olive oil, salt, black pepper, flour, butter, etc.).
- [x] Household can toggle whether an item is considered an "always-stocked staple".

**Verification:**
- [x] Tests pass: `bin/rails test test/models/pantry_item_test.rb test/controllers/pantry_items_controller_test.rb`
- [x] Manual check: Visit `/pantry`, toggle staple items on and off via Turbo Stream.

**Dependencies:** Task 3
**Files likely touched:**
- `app/models/pantry_item.rb`
- `app/controllers/pantry_items_controller.rb`
- `app/views/pantry_items/index.html.erb`
- `app/views/pantry_items/_pantry_item.html.erb`
**Estimated scope:** Small (3-4 files)

---

### Task 5: 60-Second Onboarding Wizard & 10 Curated Starter Recipes
**Description:** Build a 2-step onboarding flow for newly created households to select up to 10 family favorite starter recipes and confirm their pantry staples.

**Acceptance criteria:**
- [x] New households are directed to `/onboarding` after registration.
- [x] Step 1: Visual card selector for 10 popular family starter recipes.
- [x] Step 2: Confirmation of default pantry staples.
- [x] On completion, recipes and pantry items are cloned into the household, and user is redirected to the dashboard.

**Verification:**
- [x] Tests pass: `bin/rails test test/controllers/onboarding_controller_test.rb`
- [x] Manual check: Complete onboarding flow with 4 recipes selected; verify recipes appear in household recipe vault.

**Dependencies:** Task 4
**Files likely touched:**
- `app/controllers/onboarding_controller.rb`
- `app/views/onboarding/recipes.html.erb`
- `app/views/onboarding/pantry.html.erb`
- `config/starter_recipes.yml`
**Estimated scope:** Medium (4-5 files)

---

## Checkpoint: Onboarding & Pantry
- [x] All tests pass: `bin/rails test`
- [x] Fresh signup lands on onboarding wizard and produces a populated recipe vault with selected starter dishes.

---

## Phase 3: Recipe Vault & Scraper

### Task 6: Recipe Box CRUD & Family Member "Craving" Requests
**Description:** Implement `Recipe`, `RecipeIngredient`, and `RecipeRequest` models with responsive card views and a 1-tap "Craving / Request for Next Week" heart button.

**Acceptance criteria:**
- [x] Full CRUD for recipes (title, description, prep_time, cook_time, servings, ingredients list, instructions).
- [x] Family members can toggle "Craving" on any recipe with instant Turbo Stream count and active badge update.
- [x] Filter recipe vault by "Requested this week", "Quick (< 30 min)", and tags.

**Verification:**
- [x] Tests pass: `bin/rails test test/models/recipe_test.rb test/controllers/recipes_controller_test.rb test/controllers/recipe_requests_controller_test.rb`
- [x] Manual check: Create a custom recipe, toggle craving as "Dad", switch to "Mom" and toggle craving, verify request count is 2.

**Dependencies:** Task 3
**Files likely touched:**
- `app/models/recipe.rb`
- `app/models/recipe_ingredient.rb`
- `app/models/recipe_request.rb`
- `app/controllers/recipes_controller.rb`
- `app/views/recipes/index.html.erb`
- `app/views/recipes/show.html.erb`
- `app/views/recipes/_recipe_card.html.erb`
**Estimated scope:** Medium (5 files)

---

### Task 7: JSON-LD Web Recipe Scraper Service
**Description:** Implement `RecipeScraper` service using Nokogiri to parse `schema.org/Recipe` JSON-LD from URLs and provide an interactive "Import from URL" modal.

**Acceptance criteria:**
- [x] `RecipeScraper.call(url)` extracts title, prep_time, cook_time, servings, image_url, raw ingredients, and instructions.
- [x] Graceful error handling for unsupported sites with helpful error messages.
- [x] "Import from URL" modal previews scraped fields before user saves to recipe box.

**Verification:**
- [x] Tests pass: `bin/rails test test/services/recipe_scraper_test.rb` (with mocked HTML fixtures for JSON-LD sites)
- [x] Manual check: Paste a supported recipe URL in the modal, verify all fields auto-populate in under 2 seconds.

**Dependencies:** Task 6
**Files likely touched:**
- `app/services/recipe_scraper.rb`
- `app/controllers/recipe_imports_controller.rb`
- `app/views/recipe_imports/new.html.erb`
**Estimated scope:** Small (3-4 files)

---

## Checkpoint: Recipe Ingestion & Cravings
- [x] All tests pass: `bin/rails test`
- [x] User can scrape online recipes and family members can vote on meals.

---

## Phase 4: Weekly Meal Planner & Cook Assignments

### Task 8: 7-Day Weekly Meal Planner Grid
**Description:** Implement `MealPlan` (week_start_date) and `MealPlanSlot` (date, meal_type [lunch/dinner], recipe_id, notes) models with a 7-day visual matrix.

**Acceptance criteria:**
- [x] 7-day grid showing Monday through Sunday with Lunch and Dinner rows.
- [x] Sidebar drawer displaying household recipes and top-voted "Cravings".
- [x] 1-click or drag slotting of recipes into specific meal slots via Turbo Frames.
- [x] Quick week navigator (Previous Week / Next Week / Current Week).

**Verification:**
- [x] Tests pass: `bin/rails test test/models/meal_plan_test.rb test/controllers/meal_plans_controller_test.rb`
- [x] Manual check: Open planner for current week, add 5 dinners from sidebar drawer, verify instant Turbo update.

**Dependencies:** Task 6
**Files likely touched:**
- `app/models/meal_plan.rb`
- `app/models/meal_plan_slot.rb`
- `app/controllers/meal_plans_controller.rb`
- `app/controllers/meal_plan_slots_controller.rb`
- `app/views/meal_plans/show.html.erb`
- `app/views/meal_plans/_slot.html.erb`
**Estimated scope:** Medium (5 files)

---

### Task 9: Cook Assignment & Custom Slot Notes
**Description:** Add "Cook of the Night" assignment (`family_member_id`) to meal slots and support custom text entries (e.g. "Leftovers from Tuesday", "Dining Out").

**Acceptance criteria:**
- [x] Each meal slot allows picking an assigned cook from household family members with avatar badge.
- [x] User can enter custom meal name and notes without attaching a formal recipe.
- [x] Filter or highlight days where a specific family member is the assigned chef.

**Verification:**
- [x] Tests pass: `bin/rails test test/controllers/meal_plan_slots_controller_test.rb`
- [x] Manual check: Assign "Dad" to Tuesday tacos, add a custom note "Leftovers" for Wednesday lunch.

**Dependencies:** Task 8
**Files likely touched:**
- `app/views/meal_plans/_slot.html.erb`
- `app/controllers/meal_plan_slots_controller.rb`
**Estimated scope:** Small (3 files)

---

## Checkpoint: Weekly Planning Flow
- [x] All tests pass: `bin/rails test`
- [x] Complete weekly schedule can be populated with recipes, custom notes, and assigned cooks in under 5 minutes.

---

## Phase 5: Fridge Print View & Google Calendar iCal Feed

### Task 10: High-Contrast 1-Page Fridge Print Sheet
**Description:** Implement a dedicated `/meal_plans/:id/print` view with custom CSS `@media print` rules designed to print crisply on standard 8.5x11 / A4 single page.

**Acceptance criteria:**
- [x] Print view displays weekly grid with large, clear typography, day names, meal titles, assigned cooks, and prep notes.
- [x] Page-break constraints guarantee entire schedule fits on a single sheet of paper without overflow.
- [x] Printable view includes clean high-contrast black/white styling.

**Verification:**
- [x] Tests pass: `bin/rails test test/controllers/meal_plans_controller_test.rb`
- [x] Manual check: Trigger browser print preview (`Ctrl+P` / `Cmd+P`) on print view and verify perfect single-page layout.

**Dependencies:** Task 9
**Files likely touched:**
- `app/views/meal_plans/print.html.erb`
- `app/views/layouts/print.html.erb`
**Estimated scope:** Small (3 files)

---

### Task 11: Tokenized iCal (`.ics`) Calendar Feed Endpoint
**Description:** Generate unique household calendar tokens and serve RFC 5545 compliant `.ics` feeds at `/feeds/:token/meals.ics` for Google Calendar / Apple Calendar / Outlook subscription.

**Acceptance criteria:**
- [x] `Household` generates a secure `calendar_token` upon creation.
- [x] `/feeds/:token/meals.ics` returns valid VCALENDAR with VEVENT items for all scheduled meal plan slots.
- [x] VEVENT contains summary (`[Dinner] Tacos (Cook: Dad)`), description, and recipe details.
- [x] Modal in UI provides 1-click "Subscribe in Google Calendar / Apple Calendar" instructions.

**Verification:**
- [x] Tests pass: `bin/rails test test/controllers/feeds_controller_test.rb test/services/ical_generator_test.rb`
- [x] Manual check: Fetch `.ics` endpoint via curl, validate formatting against RFC 5545 iCalendar validator.

**Dependencies:** Task 9
**Files likely touched:**
- `app/services/ical_generator.rb`
- `app/controllers/feeds_controller.rb`
**Estimated scope:** Small (3-4 files)

---

## Checkpoint: Fridge & Calendar Integration
- [x] All tests pass: `bin/rails test`
- [x] Fridge sheet prints on 1 page and `.ics` feed subscribes cleanly to Google Calendar.

---

## Phase 6: Mobile Grocery List & Shopping Checklist

### Task 12: Supermarket Aisle Ingredient Aggregator Service
**Description:** Build `IngredientAggregator` service that aggregates all ingredients from the active meal plan, categorizes them by supermarket aisle, and filters out active pantry staples.

**Acceptance criteria:**
- [x] Groups ingredients into 7 standard supermarket categories (Produce, Meat & Seafood, Dairy, Bakery, Pantry, Spices & Baking, Frozen, Other).
- [x] Consolidates duplicate ingredient names and sums quantities where possible.
- [x] Automatically suppresses items marked as Pantry Staples, flagging them as "In Pantry".

**Verification:**
- [x] Tests pass: `bin/rails test test/services/ingredient_aggregator_test.rb`
- [x] Manual check: Plan 3 meals sharing common ingredients (e.g. onions, garlic, olive oil); verify olive oil is suppressed and onions are aggregated.

**Dependencies:** Task 8, Task 4
**Files likely touched:**
- `app/services/ingredient_aggregator.rb`
- `test/services/ingredient_aggregator_test.rb`
**Estimated scope:** Small (2 files)

---

### Task 13: Mobile PWA Grocery Shopping Checklist
**Description:** Build a mobile-friendly `/meal_plans/:id/grocery_list` view with 1-tap strike-through, categorized aisle sections, and "Pantry Shield" toggle.

**Acceptance criteria:**
- [x] Responsive, touch-optimized shopping checklist view.
- [x] Tapping an item marks it crossed off / completed with instant state persistence (localStorage / Hotwire).
- [x] Toggle button: "Show Pantry Items (X items hidden)" to inspect and un-suppress staples.

**Verification:**
- [x] Tests pass: `bin/rails test test/controllers/grocery_lists_controller_test.rb`
- [x] Manual check: Open grocery list on mobile viewport, tap items to cross off, toggle pantry staples.

**Dependencies:** Task 12
**Files likely touched:**
- `app/controllers/grocery_lists_controller.rb`
- `app/views/grocery_lists/show.html.erb`
- `app/javascript/controllers/checklist_controller.js`
**Estimated scope:** Medium (4 files)

---

## Final Checkpoint: End-to-End Verification
- [x] All test suites pass: `bin/rails test` (62 tests, 168 assertions, 0 failures)
- [x] Assets compile cleanly: `bin/rails tailwindcss:build`
- [x] Complete full user journey supported:
  1. Register new household with Rails 8 native auth
  2. Complete 60-second onboarding with starter recipes & pantry staples
  3. Scrape a new recipe from URL (JSON-LD) or manual entry
  4. Family member casts a craving vote
  5. Build 7-day meal plan with assigned cooks in < 5 minutes
  6. Print 1-page fridge calendar sheet
  7. Subscribe via Google Calendar `.ics` feed
  8. Open grocery list on mobile and check off items
