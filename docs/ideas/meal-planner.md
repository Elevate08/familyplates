# MealHub: The 5-Minute Family Meal Planner

## Problem Statement
How might we enable a busy household to collaboratively plan meals in under 5 minutes, producing a beautiful fridge-ready calendar, an automated Google Calendar feed, and an aisle-organized mobile grocery list with zero administrative overhead?

## Recommended Direction
A lightweight, DRY **Ruby on Rails 8 (Hotwire / Turbo / Stimulus)** application designed specifically for household collaboration.

The application bridges the three critical touchpoints of family meal planning:
1. **The Fridge:** High-contrast, beautifully styled 1-page `@media print` physical sheet for glanceable kitchen viewing.
2. **Personal Devices & Google Calendar:** Zero-overhead tokenized `webcal://` `.ics` feed syncing meal schedules straight into family calendars.
3. **The Grocery Store:** Responsive mobile PWA checklist aggregating ingredients by aisle with intelligent "Pantry Shield" staple suppression.

### Core User Journey
1. **Onboarding in 60 Seconds:**
   - Account setup using Rails 8 native auth (`has_secure_password`).
   - Create family member profiles (e.g. *Mom*, *Dad*, *Kids*).
   - Select from **10 Curated Starter Recipes** to immediately populate the recipe vault.
   - Confirm the default **Pantry Staples Checklist** (salt, olive oil, flour, butter, etc.) so staple ingredients don't clutter grocery lists.
2. **Weekly Planning in Under 5 Minutes:**
   - Family members tap "Request / Heart" on recipes they crave during the week from their phones.
   - The primary planner drags requested recipe cards onto Lunch & Dinner slots (Monday–Sunday) and assigns an optional cook.
3. **Instant Automated Outputs:**
   - Print the 1-page fridge calendar.
   - Google Calendar auto-refreshes via the `.ics` feed.
   - Grocery list is automatically compiled, organized by supermarket aisle (Produce, Dairy, Meat, Bakery, Pantry, Spices), ready for mobile shopping.

---

## Technical Architecture & DRY Design

### Stack
- **Framework:** Ruby on Rails 8
- **Frontend / Realtime:** Hotwire (Turbo Drive, Turbo Frames, Turbo Streams) + Stimulus JS
- **Styling:** Tailwind CSS + custom `@media print` stylesheets
- **Database:** PostgreSQL / SQLite (with solid_cache, solid_queue, solid_cable)
- **Authentication:** Rails 8 Native Authentication (`rails generate authentication`) + Household profile switching
- **Calendar Integration:** Standard `.ics` VEVENT feed (no Google OAuth API maintenance required)
- **Recipe Ingestion:** Nokogiri service object extracting `schema.org/Recipe` JSON-LD metadata

### Data Model
```
Household
├── Users (Account Owners / Admins)
├── FamilyMembers (name, avatar_color, role)
├── Recipes (title, prep_time, cook_time, servings, source_url, instructions, tags)
│   └── RecipeIngredients (raw_text, name, quantity, unit, aisle_category)
├── PantryItems (name, is_staple)
├── MealPlans (week_start_date, status)
│   └── MealPlanSlots (day_of_week, meal_type [lunch/dinner], Recipe, FamilyMember [cook])
└── RecipeRequests (Recipe, FamilyMember, week_start_date)
```

---

## Key Assumptions to Validate
- [ ] **JSON-LD Recipe Scraper Coverage:** Validate that `schema.org/Recipe` parsing successfully handles 85%+ of popular family recipe sites (AllRecipes, NYT Cooking, BudgetBytes, Serious Eats, Food Network).
- [ ] **iCal Sync Refresh Interval:** Verify Google Calendar external calendar polling frequency meets family expectations for weekly updates.
- [ ] **Ingredient Normalization Simplicity:** Ensure lightweight regex-based ingredient categorization (Produce, Meat, Dairy, Pantry) is sufficiently accurate without heavy NLP dependencies.

---

## MVP Scope (v1)

### 1. Auth & Household Setup
- Rails 8 native auth for household account owner.
- Family member profiles with 1-tap quick switcher.
- Onboarding wizard with 10 pre-loaded popular family recipes & editable pantry staples preset.

### 2. Recipe Box & Scraper
- Quick URL importer (auto-fetches title, image, ingredients, prep time via JSON-LD).
- Manual recipe creator (markdown instructions + ingredient list).
- Family member recipe request / upvote button.

### 3. Weekly Meal Planner
- 7-day visual matrix (Monday–Sunday × Lunch / Dinner).
- Drag-and-drop / 1-tap slot assignment from recipe drawer.
- "Cook of the Night" assignment badge per slot.

### 4. Fridge Sheet (Print Layout)
- Dedicated print stylesheet (`@media print`) fitting 8.5x11 / A4 single page.
- Clean typography displaying daily meals, assigned cooks, and notes.

### 5. Google Calendar / iCal Feed
- Tokenized calendar subscription URL (`/households/:token/meals.ics`).
- Auto-generates standard all-day or dinner-timed `VEVENT` items with recipe links and assigned cook names.

### 6. Aisle-Organized Grocery List
- Auto-aggregates quantities across all planned meals for the week.
- Categorized by supermarket section (Produce, Meat & Seafood, Dairy & Refrigerated, Pantry & Grains, Spices & Baking, Frozen).
- Interactive mobile check-off with strike-through.
- "Pantry Shield" filter to hide common staples.

---

## Not Doing (and Why)
- **Full 2-Way Google Calendar Editing:** Google API OAuth tokens expire and create sync conflicts; a 1-way `webcal://` feed is zero-maintenance, rock-solid, and works on Google, Apple, and Outlook calendars.
- **Calorie / Micronutrient Tracking:** High cognitive friction and massive database overhead that detracts from fast family dinner coordination.
- **Direct Supermarket Delivery API Integrations (Instacart/Amazon Fresh):** High partner API churn and maintenance; in-store mobile checklist or copyable text covers actual family needs with zero breakage.
- **Complex Multi-Tenancy / Enterprise Permissions:** Keeps the Rails models clean, DRY, and fast.
- **Dedicated Kiosk Hardware Mode:** Deferred to post-v1; responsive mobile PWA and the printable fridge sheet solve immediate physical needs.

---

## Open Questions & Future Enhancements (Post-v1)
- **Kiosk / E-Ink Display Mode:** Dedicated dark/ambient screen view optimized for wall-mounted tablets or Raspberry Pi screens.
- **Leftover Management:** Quick button to mark "Tonight's dinner = Tomorrow's lunch".
- **Batch Export:** One-click export of the grocery list to Apple Reminders or Todoist via URL schemes.
