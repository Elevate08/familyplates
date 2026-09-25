# Changelog

All notable changes to FamilyPlates are documented in this file.

## [v1.3.0] - Unreleased

FamilyPlates can now run as a hosted, multi-household service with Stripe billing and a private operator console. Appliance mode stays free, single-household and fully offline-capable. Sign-in, sessions and device pairing were rebuilt for multiple households, and every route is now tested against every kind of visitor.

### ⚠️ Upgrading from v1.2.0
* **Back up the database first.** Household and family-member IDs move from integers to UUIDs, along with the seven foreign keys that point at them. The migration keeps every relationship and has a tested rollback, but it rewrites core tables.
* **Existing sessions keep working.** Session tokens are hashed in place, so nobody is signed out. Rolling back that migration clears sessions, because the hashes can't be reversed.
* **Google Calendar direct sync is gone.** Use the calendar subscription feeds instead. The migration drops the stored service-account settings.
* **Hosted mode refuses to boot without `APP_HOST` and `SMTP_ADDRESS`.** It also forces HTTPS by default: set `FORCE_SSL` to override, or `ASSUME_SSL` behind a TLS-terminating proxy. Appliance mode is unchanged.
* **Signing in is opt-in on an appliance.** `REQUIRE_LOGIN` can only be turned on once at least one admin profile has a linked account with a password.
* **Hosted billing needs a Stripe webhook endpoint** subscribed to the right events. See [docs/hosted/stripe-billing.md](docs/hosted/stripe-billing.md).

### 📄 License
* **FamilyPlates is now under the [O'Saasy License](LICENSE.md).** It's MIT plus one condition: you may not offer FamilyPlates to others as a competing hosted service. Self-hosting, modifying and sharing it stay free. Earlier releases were labelled MIT.

### 🚀 Highlights
* **Hosted multi-household mode** (`FAMILYPLATES_MODE=hosted`): public sign-up, per-household onboarding, and tenant isolation for every record.
* **Subscriptions and billing through Stripe** (via Pay): a 14-day free trial, $4/month or $35/year, a 7-day grace period on a failed payment, a Stripe billing portal, and access that lasts to the end of a cancelled period.
* **Operator console** at `/platform_admin`, behind its own password, TOTP and rate limit. It has a household health view, household activity, support conversations, reversible suspension, export and deletion requests, promotion programs, guarded bulk operations and a filterable audit log.
* **Calendar subscriptions** (`.ics`/`webcal`) with one-tap setup for Apple, Google and Outlook.
* **Cook Mode:** a distraction-free, step-by-step kitchen screen with countdown timers, an ingredient drawer and a screen wake lock. `/cook` opens whichever meal is due by the household's own serving times.

### 👥 Accounts, sign-in & devices
* Accounts are separate from household profiles, so one person can belong to several households and switch between them from the profile menu.
* Appliances sign in with a password; hosted sign-in uses single-use 6-character email codes. Both give the same response for known and unknown emails, and both are rate-limited.
* Passkeys (WebAuthn), plus sign-in with Google, Apple, generic OIDC, or a trusted forward-auth proxy.
* Kiosk device pairing (RFC 8628) with restricted kiosk sessions, a connected-devices list, and revoking one device or all of them.
* Browser sessions slide: 30 days idle, 90 days at most. Join codes can be reset, and profiles can be handed to another device through a 4-hour signed link with a QR code.
* Changing an admin's preferences asks for their PIN.

### 💳 Billing & operator console
* **Operators can cancel a subscription** (at period end or immediately), **refund a charge** (in full or part) and **comp free months** from a household's page. Comping moves the next Stripe charge back, so annual plans work too; for a household that isn't paying, it extends the free trial. Each action needs a reason for the audit log, and only `owner` and `billing` operators can take them.
* **An operator-assigned promotion is now applied at Stripe Checkout.** Before, assigning one only changed the household record, and the promotion-code ID never reached Stripe.
* **Promotion redemption counts come from Stripe** and refresh on every new subscription, including codes typed at Checkout. A program that has reached its limit stops being applied.
* Operator roles are enforced for billing: `support` and `privacy` operators can see billing but not change it.
* Coming back from Checkout activates the kitchen immediately, without waiting for the webhook.
* The operator sees every charge state: paid, pending, uncaptured, failed, refunded, partially refunded and disputed.

### 🍳 Recipes, pantry & planning
* Leftovers have a capacity and a shelf life. A cooked meal feeds later slots until it runs out or goes past its date, and clearing a slot cleans up the leftovers that came from it.
* Pantry staples can be flagged as running low from the pantry or from a recipe. They then join the grocery list, and ticking them off marks them restocked.
* Recipes and meal plans are numbered per household.
* The recipe URL importer handles JSON-LD, microdata and failed fetches more reliably.
* The planner has a date-range picker with a calendar popover, and dates follow the household's time zone.
* Recipe images from CDNs that block hotlinking now load, and a placeholder shows when one fails.

### 🔐 Security
* A meal slot accepted any household's recipe ID, so one household could read another's recipe. Fixed, along with the other cross-tenant and sign-up gaps a new route-by-role authorization table found.
* Nobody signed in now means no household at all. Before, anonymous requests resolved to the installation's household, which hid missing scope checks.
* Session tokens are stored as SHA-256 hashes, and a device-pairing code can't be reused.
* Sign-in codes stay out of the log at debug level, and PINs and passkey credentials are filtered from request logs.
* Operator sign-in shares the household sign-in's rate limit.
* A blank organizer PIN at sign-up is no longer stored as `1234`. Uploaded recipe images must be images under 8 MB, `%` in a search is no longer a wildcard, and calendar feeds can't be cached publicly.

### 🐛 Correctness
* **Operator bulk operations didn't work in a browser.** Turbo discarded the preview page, so **Preview** did nothing.
* A bad `?week=` or `?month=` parameter no longer causes a server error.
* A calendar feed no longer drops a meal whose custom title happens to be "No Meal Planned".
* 27 tests failed on Mondays and Tuesdays, when fixture slots collided with the day's slots.

### ♿ Accessibility
* Every page is checked with axe for every kind of visitor. Named the icon-only buttons, colour swatches, grocery checkboxes, ingredient fields and operator form fields, and declared the page language on the cook and print layouts.

### 🧪 Testing & CI
* A Playwright suite visits every GET route as every kind of visitor. It checks for server and JavaScript errors, broken assets, horizontal scroll on a phone, and accessibility, and it compares screenshots in light, dark and mobile. It runs in a pinned container, sharded across three CI runners.
* Signed Stripe webhook tests cover every charge and subscription state, plus Checkout completion, new subscriptions, failed-payment emails and invoice updates.
* Real Stripe sandbox tests pay through Checkout, comp and cancel that subscription from the console, and confirm an assigned promotion is applied. They only run with a test key, and the suite refuses to start with a live key.
* Every Fizzy acceptance criterion is linked to the tests that prove it, and CI fails when a criterion has no test.
* CI actions are pinned to commit SHAs and don't get credentials they don't need.

### 🧹 Removed
* The `hosted:simulate_customers` and `scale:validate` development rake tasks. Their results are recorded in `docs/ideas/household-identity-and-tenancy.md`.
* Dead code: an orphaned landing view, the sample `hello` controller, and unused model methods.

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
