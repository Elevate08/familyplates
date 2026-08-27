# Implementation Plan: MealHub - 5-Minute Family Meal Planner

## Overview
MealHub is a lightweight, DRY Ruby on Rails 8 application designed to make family meal planning effortless. It bridges three core household touchpoints: an `@media print` 1-page fridge calendar, a zero-maintenance `webcal://` `.ics` Google Calendar feed, and an aisle-organized mobile grocery shopping list with pantry staple filtering.

---

## Architecture & Design Decisions

### 1. Framework & Infrastructure
- **Ruby on Rails 8** with SQLite3 (leveraging `solid_cache`, `solid_queue`, and `solid_cable`).
- **Hotwire (Turbo Drive, Turbo Frames, Turbo Streams) + Stimulus JS:** Realtime, responsive UI with zero heavy frontend framework overhead.
- **Tailwind CSS:** Modern, accessible styling with dedicated `@media print` stylesheets.

### 2. Multi-Profile Family Authentication
- **Rails 8 Native Auth (`rails generate authentication`):** Account owner manages the household account with email and password (`has_secure_password`).
- **Family Member Profiles:** Lightweight profiles (`FamilyMember`) with avatars and color badges. A 1-tap switcher in the navigation sets `Current.family_member` via a signed session cookie, allowing kids and partners to vote on meals without separate login credentials.

### 3. Recipe Ingestion & Scraping
- **JSON-LD Scraper (`RecipeScraper` service):** Extracts `schema.org/Recipe` structured metadata (title, prep time, servings, ingredients, instructions, image) using Nokogiri, falling back to OpenGraph metadata.
- **Manual Markdown Recipe Creator:** Fast text entry for family handwritten recipes.

### 4. Calendar Integration
- **1-Way iCal Feed:** Secure tokenized endpoint (`/feeds/:token/meals.ics`) generating standard RFC 5545 VEVENTs. Avoids complex Google OAuth2 refresh tokens and works natively with Google Calendar, Apple Calendar, and Outlook.

### 5. Grocery Aggregation & "Pantry Shield"
- **Aisle Categorizer (`IngredientAggregator` service):** Categorizes ingredients into Produce, Meat & Seafood, Dairy & Refrigerated, Bakery, Pantry & Grains, Spices & Baking, Frozen, and Other.
- **Pantry Shield:** Automatic suppression of confirmed pantry staples (salt, olive oil, pepper, flour, butter) with 1-tap unhide toggle in the grocery checklist.

---

## Dependency Graph

```
Phase 1: Foundation
  ├── Rails 8 Skeleton & Tailwind Config (Task 1)
  ├── Household & Native Auth Models (Task 2)
  └── Family Profile Switcher (Task 3)
        │
Phase 2: Onboarding & Pantry
  ├── Pantry Items & Default Staples (Task 4)
  └── 60-Second Onboarding Wizard & 10 Starter Recipes (Task 5)
        │
Phase 3: Recipe Vault
  ├── Recipe Box & Family Craving Requests (Task 6)
  └── JSON-LD Recipe Scraper Service (Task 7)
        │
Phase 4: Weekly Meal Planner
  ├── 7-Day Planning Grid Matrix (Task 8)
  └── Cook of the Night & Custom Slot Notes (Task 9)
        │
Phase 5: Physical & Digital Outputs
  ├── 1-Page Fridge Print View (@media print) (Task 10)
  └── Tokenized iCal Calendar Feed (.ics) (Task 11)
        │
Phase 6: Mobile Grocery List
  ├── Aisle Ingredient Aggregator Service (Task 12)
  └── Mobile PWA Shopping Checklist (Task 13)
```

---

## Task List

### Phase 1: Project Setup, Data Foundations & Native Auth
- [ ] **Task 1:** Initialize Rails 8 app with Tailwind CSS, SQLite, and Minitest/RSpec test suite.
- [ ] **Task 2:** Implement Household, User, Session models and Rails 8 native authentication.
- [ ] **Task 3:** Build Family Member profile switcher and `Current.family_member` context.

### Checkpoint: Foundation
- [ ] All tests pass.
- [ ] User can sign up, log in, create family member profiles, and switch active profile.

---

### Phase 2: Onboarding Wizard & Starter Pack
- [ ] **Task 4:** Create PantryItem model and pre-seeded default Pantry Staples checklist.
- [ ] **Task 5:** Build 60-second onboarding wizard with 10 selectable family starter recipes.

### Checkpoint: Onboarding & Pantry
- [ ] New household completes onboarding, populates recipe vault with selected starters, and configures pantry staples.

---

### Phase 3: Recipe Vault & Scraper
- [ ] **Task 6:** Build Recipe Box CRUD and family member "Craving / Request" upvoting.
- [ ] **Task 7:** Implement JSON-LD Recipe Scraper service object (`RecipeScraper`) with Nokogiri.

### Checkpoint: Recipe Ingestion & Requests
- [ ] Users can import recipes from external URLs via JSON-LD or create them manually; family members can toggle cravings.

---

### Phase 4: Weekly Meal Planner & Cook Assignments
- [ ] **Task 8:** Build 7-day (Mon–Sun × Lunch/Dinner) weekly meal planner grid with Hotwire slotting.
- [ ] **Task 9:** Implement "Cook of the Night" assignment badge and custom text meal slots (e.g. "Leftovers").

### Checkpoint: Weekly Planning Flow
- [ ] Household can build a full 7-day meal plan with assigned cooks in under 5 minutes.

---

### Phase 5: Fridge Print View & Google Calendar iCal Feed
- [ ] **Task 10:** Create 1-page high-contrast `@media print` fridge calendar view (`/meal_plans/:id/print`).
- [ ] **Task 11:** Implement tokenized `webcal://` `.ics` calendar feed endpoint (`/feeds/:token/meals.ics`).

### Checkpoint: Fridge & Calendar Integration
- [ ] Fridge sheet prints cleanly on standard 8.5x11 / A4 paper; calendar feed validates in iCal/Google Calendar.

---

### Phase 6: Mobile Grocery List & Shopping Checklist
- [ ] **Task 12:** Implement `IngredientAggregator` service with supermarket aisle categorization and pantry filtering.
- [ ] **Task 13:** Build responsive mobile PWA grocery shopping checklist with 1-tap strike-through.

### Final Checkpoint: Complete End-to-End Verification
- [ ] Full end-to-end user journey works: Signup → Onboarding → Recipe Scrape → Weekly Plan → Fridge Print → Calendar Sync → Grocery Shopping.

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
| :--- | :--- | :--- |
| **Recipe sites with non-standard markup** | Medium | JSON-LD covers 85%+ of recipe sites; fallback gracefully to OpenGraph title/description and provide an editable preview modal so user can correct fields before saving. |
| **Messy ingredient line duplicates** | Medium | Rule-based aggregator normalizes common ingredient names (e.g. "garlic cloves" → "Garlic") and groups by grocery aisle without needing heavy external NLP. |
| **Print layout spilling onto page 2** | Low | Strict CSS `@media print` rules using `page-break-inside: avoid`, compact grid rows, and fixed aspect ratio container for 8.5x11 / A4 dimensions. |
| **Google Calendar sync lag** | Low | Clarify in UI that Google Calendar polls external feeds every 8–24 hours, while Apple Calendar and Outlook allow manual / 15-minute refresh. |
