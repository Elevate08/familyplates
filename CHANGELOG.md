# Changelog

All notable changes to FamilyPlates are documented in this file.

## [v1.2.0] - 2026-09-02

A security, correctness and performance release. Three independent reviews of the
v1.1.0 tree were reconciled into one plan; every finding was verified against the
code before it was acted on, and each fix was confirmed failing against the
pre-fix version first.

### 🔐 Security
* **Refuse to boot on a guessable `SECRET_KEY_BASE`.** The published default let anyone forge a signed session cookie and take over an install without credentials.
* **PINs are stored as bcrypt digests** (`has_secure_password :pin`), not plaintext, and compared with `secure_compare`. Two migrations add the digest and drop the plaintext column.
* **Google service-account JSON is encrypted at rest** via Active Record Encryption.
* **Rate-limited PIN attempts** by IP and by profile, so a 4-digit PIN cannot be walked through.
* **Closed five stored-XSS sinks**, including a `raw()` helper that rendered a user-typed pantry icon straight into the page.
* **SSRF egress filtering on recipe import.** Requests are checked by *resolved* address and pinned to it, so a public hostname cannot redirect into private space or the cloud metadata service.
* **The onboarding wizard is no longer reachable without a session** once a household exists. It was exempted by controller path, which left the roster, recipe and pantry steps open.
* Session cookies are marked `secure` over TLS, and the CSP nonce is stable across a Turbo navigation.

### 🐛 Correctness
* Moving a meal slot happens in one transaction; a failed move no longer destroys the original.
* A renamed ingredient re-syncs its old aisle mapping instead of stranding it.
* Starter recipe images render again, with the utensils placeholder behind them.
* Ingredient rows added in quick succession keep their own names — the row index was time-based and could collide inside a millisecond.
* Panels focus their input directly instead of from a timer, so a deferred callback can no longer pull the caret out of the field you are typing in. The bulk tag modal focused a hidden field and had never placed the caret at all.
* Emoji pantry icons take the size their caller asks for, matching the drawn icons beside them.

### ⚡ Performance
* Saving a 15-ingredient recipe: **211 queries → 91**.
* Grocery auto-fulfilment: **37 queries → 14**, batched and scoped.
* A 20-ingredient edit page: **455KB → 235KB**, emitting the ingredient catalogue once.

### ♿ Accessibility & UI
* Pinch-zoom restored (`maximum-scale` and `user-scalable=no` removed, WCAG 1.4.4).
* Every form field carries a label that points at it; scrollable menus stay out of the tab order.
* Dropdowns are keyboard-navigable and close when focus leaves them.
* Native controls stay native, themed to match the app rather than replaced.

### 🧪 Testing
* **319 unit and integration tests, plus 33 system tests** in a new headless-browser harness (up from 244 at v1.1.0), covering flows that had only ever been checked by hand.
* Every Stimulus controller is asserted to actually register — a dead controller shipped in v1.1.0 because request tests render HTML but never run it.
* The app version is now visible on the admin dashboard, and a test fails if the `VERSION` file, this changelog and the constant drift apart.

---

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
