# Changelog

All notable changes to FamilyPlates are documented in this file.

## [v1.1.0] - 2026-08-30

### 🚀 Highlights
* **Profile-Only Authentication Model:** Eliminated master email/password logins in favor of 1-tap family cook profile switching with 4-digit PIN verification for Organizers.
* **4-Step Onboarding Wizard:** Interactive first-boot setup covering household branding, family roster & PINs, starter recipe vault, and On-Hand pantry baseline.
* **Structured Ingredients & Weighted Aisle Learning:** 4-field ingredient form with live measurement units, global ingredient autocomplete, and dynamic aisle prediction trained on household recipes.
* **On-Hand Pantry Shield:** Replaced "Staple" terminology with "On Hand", added interactive shield toggle buttons (`shield-check` / `shield-outline`), and a floating searchable icon picker dropdown.
* **Role-Based Access Control:** Restricted meal planning slot mutations, recipe editing/creation/deletion, URL imports, and grocery list check-off to Organizer (Admin) accounts, while providing kids/members with a clean read-only view and craving requests.
* **Plaintext Markdown Grocery Export:** Instant copy of shopping lists formatted with `- [x]` (on hand / purchased) and `- [ ]` (required) markdown checkboxes.
* **Docker-First Deployment & GitHub Wiki:** Added production `docker-compose.yml` for 1-command startup and synchronized complete documentation to the GitHub Wiki.

### 👥 Authentication & Administration
* Removed legacy `User` and `Session` password tables; authentication is now purely profile-driven.
* Added Organizer 4-digit PIN verification modal on profile switch.
* Created dedicated `/admin/calendar/edit` page for Google Calendar Direct Sync credentials, live connectivity tester, and 1-click week sync.
* Built User Preferences portal (`/preferences`) for avatars, accent colors, and PIN management.

### 🍳 Recipes & Pantry
* Upgraded recipe tag picker with live search, badge pills, and instant custom tag creation.
* Enforced uniform image heights and `object-cover` scaling across recipe cards.
* Converted pantry category selector to peer-checked radio inputs for instant CSS active state switching.
* Built searchable floating dropdown icon picker supporting custom SVGs and emojis.

### 🛒 Grocery & Meal Planning
* Non-admin family members see a read-only grocery checklist and cannot uncheck or reset items.
* "Copy Plain Text" outputs organized aisle sections with `- [x]` / `- [ ]` checkboxes.
* Mobile-optimized meal planner header with quick print button for 1-page fridge schedules.

---

## [v1.0.2] - 2026-08-28
* Auto-refresh leftover buttons via Turbo Streams.
* Enhanced dark mode support in monthly planner and print preview.

## [v1.0.1] - 2026-08-26
* Dependency security updates (`image_processing` 2.0.3, `ruby-vips`).
* CI workflow updates and RuboCop linting rules.

## [v1.0.0] - 2026-08-25
* Initial public release: Full family meal planner with leftovers, PWA support, Google Calendar background sync, and dark mode.
