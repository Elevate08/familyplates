# Implementation Plan: v1.1.0 Quality & Security Remediation

**Baseline:** `49549db` (tag `v1.1.0`, == `master`)
**Reconciles:** `docs/code-review-quality-report.md` (QR), `docs/code-review-findings-claude-2026-09-01.md` (CL), `docs/code-review-findings-codex-2026-09-01.md` (CX)
**Task list:** `tasks/todo.md`
**Superseded artifacts:** `tasks/archive/v1.1.0-plan.md`, `tasks/archive/v1.1.0-todo.md`

---

## Overview

Three independent reviews of the v1.1.0 tree produced 29 distinct defects after
deduplication. The v1.1.0 image is published to `ghcr.io` and tagged `latest`, so
this plan splits into two delivery streams:

- **Stream A — `v1.1.1`, out-of-band patch.** Everything an unauthenticated
  visitor can reach, plus flows that are outright broken for people already
  running the image. 11 tasks, code-only, **no schema migration**.
- **Stream B — `v1.2.0`, next release.** Secret-at-rest migrations, architecture
  cleanup, performance, accessibility. 16 tasks.

The suite is **RED at HEAD** (172 runs, 657 assertions, 1 failure — reproduced
locally, see Verification Log). **Task 0 is the only task that may assume a red
suite.** Every checkpoint from A1 onward requires green.

---

## Verification Log

Every finding below was checked against the code at `49549db` before it entered
this plan. Both source documents label some findings `PLAUSIBLE`; those were
treated as unverified claims. Verification methods used:

- **PROBE** — a throwaway `ActionDispatch::IntegrationTest` (8 probes) written to
  `test/integration/`, run under `PARALLEL_WORKERS=1`, and deleted. The tree is
  unmodified; nothing was committed.
- **SUITE** — full `bin/rails test` run.
- **RUBY** — standalone `ruby -e` script exercising the algorithm or library in
  isolation.
- **CODE** — direct read of the cited lines plus their callers/templates.

### Findings promoted from PLAUSIBLE to CONFIRMED

| ID | Finding | Source verdict | Method | Evidence |
|---|---|---|---|---|
| F2 | Anonymous → admin PIN takeover | CL#2 `PLAUSIBLE` | PROBE | `POST /set_profile/<member two>` returned 302 + set the cookie **with no PIN** (`requires_pin?` is false for non-admins); the follow-up `PATCH /family_members/<admin id>` with `pin=0000` returned 302 and `admin.reload.pin == "0000"`. **Escalates the finding: no credential is needed at all**, not merely a signed-in child profile as CL and CX both assumed. |
| F6 | Pantry 500 on invalid submit | CL#6 `CONFIRMED` (re-verified) | PROBE | `POST /pantry_items` with `name: ""` and `Accept: text/vnd.turbo-stream.html` raised `ActionView::MissingTemplate: Missing template pantry_items/index, application/index with {..., formats: [:turbo_stream], ...}`. `app/views/pantry_items/` contains only `index.html.erb` and `_pantry_item.html.erb`. |
| F8 | Non-GET `return_to` replayed as GET | CL#8 `PLAUSIBLE` | PROBE | Unauthenticated `POST /meal_plan_slots` stored `"http://www.example.com/meal_plan_slots"`; `profiles#set` redirected there; following it returned **404**, not the `RoutingError` CL predicted. Confirmed as a real defect, downgraded in severity — it is a dead-end page, not a 500. |
| F15 | Explicit "Other" aisle overwritten | CL#10 `PLAUSIBLE` | PROBE | `recipe.recipe_ingredients.create!(name: "Chicken Breast", aisle_category: "Other")` persisted as `"Meat & Seafood"`. `"Other"` is a real member of `RecipeIngredient::AISLE_CATEGORIES` and a selectable option at `_recipe_ingredient_fields.html.erb:97`. |
| F23 | Aisle-learning callback query storm | CL#12 `PLAUSIBLE` | PROBE | Instrumented `sql.active_record` across 15 sequential `recipe_ingredients.create!` calls: **211 non-SCHEMA/TRANSACTION queries**, ≈14 per ingredient. Matches the predicted mechanism (`normalize_fields` → `most_likely_aisle`, then `after_save` → `sync_ingredient_usage!` looping all 8 `AISLE_CATEGORIES` with a `find_by` + `save!`/`destroy` each). |
| F7 | Non-transactional slot move | CX Required | PROBE + CODE | `existing_dest_slot&.destroy` (`meal_plan_slots_controller.rb:63`) precedes `@slot.update` (`:73`); the `update` action body contains no `transaction`. |
| F1 | Anonymous onboarding admin creation | CL#1 `CONFIRMED` (re-verified) | PROBE | On a seeded install, anonymous `POST /onboarding/add_member` with `role=admin&pin=9999` returned 302; admin count went 1 → 2; the created row is `{"role" => "admin", "pin" => "9999"}`. Root cause is `authentication.rb:52`, which returns early for **any** `controller_path.start_with?("onboarding")` — the `allow_unauthenticated_access only: %i[family save_family]` declaration at `onboarding_controller.rb:2` is therefore dead. |
| F14 | `:role` silently dropped | QR Required | PROBE | `POST /family_members` with `role=admin&pin=4321` persisted `{"role" => "member", "pin" => nil}`. The select exists at `app/views/family_members/index.html.erb:108-109`; `family_member_params` (`:69`) permits only `[:name, :avatar_color, :avatar_icon, :pin]`. |
| F5 | Month-boundary defect | CL#7 / CX / QR | SUITE | `PARALLEL_WORKERS=1 bin/rails test` → **172 runs, 657 assertions, 1 failures, 0 errors, 0 skips**, failing at `test/controllers/meal_plans_controller_test.rb:91`. Baseline reproduced exactly as all three documents report it. |
| F10, F11 | Stored XSS via `innerHTML` | CL#4, CL#5 `PLAUSIBLE` | CODE | Raw interpolation confirmed at `tag_picker_controller.js:191`, `ingredient_autofill_controller.js:82` and `:210`. Not browser-executed here, but see **F12**: `config/initializers/content_security_policy.rb` is commented out in its entirety, so no CSP header is emitted and an injected inline handler has nothing stopping it. Treated as CONFIRMED-by-inspection. |
| F9, F24, F25, F27, F19, F20, F21, F22, F26 | — | CL/QR `PLAUSIBLE` or `Consider` | CODE | Each cited line read and confirmed present as described. `current_household.meal_plan_slots` exists (`household.rb:6`), so the F21 simplification is valid as written. |

### Claims that verification **refuted** or corrected

These are the reasons three documents could not simply be concatenated.

1. **"Arbitrary local file read" in `RecipeScraper` — REFUTED.** QR calls it a
   `file:///etc/passwd` read; CX calls it "local-file access". Verified by RUBY:

   ```
   file:///etc/hostname -> URI::File  respond_to?(:open)=false
   /etc/hostname        -> URI::Generic respond_to?(:open)=false
   ftp://example.com/x  -> URI::FTP   respond_to?(:open)=true
   http://169.254.…     -> URI::HTTP  respond_to?(:open)=true
   ```

   `open-uri` mixes `OpenURI::OpenRead` into `URI::HTTP`/`HTTPS`/`FTP` only.
   A `file:` URL raises `NoMethodError`, which the bare `rescue StandardError`
   at `recipe_scraper.rb:41` swallows into `nil`. **The SSRF is entirely real**
   (loopback, RFC1918, `169.254.169.254`, and the Docker bridge are all
   reachable, and `ftp://` is an unremarked-on third scheme) — but the local
   file read is not, and the plan does not claim it. This matters: it is the
   difference between "reads the host filesystem" and "makes outbound requests",
   and it changes nothing about the fix, which must be egress filtering either
   way.

2. **QR's word-boundary remedy for staple matching is insufficient — REJECTED.**
   QR proposes `n.match?(/\b#{Regexp.escape(s)}\b/)`. Measured by RUBY against
   the actual stock `PantryItem::DEFAULT_STAPLES` list (16 entries: salt, black
   pepper, olive oil, vegetable oil, garlic powder, onion powder, italian
   seasoning, all-purpose flour, granulated sugar, soy sauce, butter, eggs,
   garlic, onions, rice, pasta):

   | Ingredient | current | QR word-boundary | exact match |
   |---|---|---|---|
   | Butternut squash | ✗ wrong | ✓ fixed | ✓ |
   | Buttermilk | ✗ wrong | ✓ fixed | ✓ |
   | Peanut butter | ✗ wrong | **✗ still wrong** | ✓ |
   | Salted butter | ✗ wrong | **✗ still wrong** | ✓ |
   | Rice vinegar | ✗ wrong | **✗ still wrong** | ✓ |
   | Rice noodles | ✗ wrong | **✗ still wrong** | ✓ |
   | Pasta sauce | ✗ wrong | **✗ still wrong** | ✓ |
   | Garlic bread | ✗ wrong | **✗ still wrong** | ✓ |
   | Green onions | ✗ wrong | **✗ still wrong** | ✓ |
   | Brown rice | ✗ wrong | **✗ still wrong** | ✓ |

   The word-boundary fix repairs 3 of 10 real-world false positives. See D5.

3. **QR's illustrative examples are not stock-reachable.** QR's headline cases
   (`steak`/`tea`, `juice`/`ice`, `peppercorns`/`corn`) require staples named
   *Tea*, *Ice* or *Corn*, none of which are in `DEFAULT_STAPLES`. They are
   reachable — users add arbitrary pantry items — but the defect's
   out-of-the-box impact is the table above, which is what the acceptance
   criteria in Task A7 are written against.

4. **CX's `.gitignore` finding is only half-reproducible.** The missing ignore
   rules are confirmed (`.gitignore` has no entry for `cookies.txt` or
   `test_output.txt`). The artifacts themselves **do not exist in this
   worktree** — `ls` reports no such files. CX reviewed the primary checkout.
   Task B14 therefore adds the rules but records no rotation work; if a real
   `cookies.txt` exists in the primary checkout it must be shredded and the
   cookie invalidated there. `config/*.json` is already ignored, which covers
   the service-account file.

5. **CL#8's predicted `RoutingError` is actually a 404.** Real defect, lower
   severity than described. Reflected in its placement (A11, not a Stream A
   security task).

### New findings, from neither document

| ID | Finding | Method |
|---|---|---|
| **F12** | `config/initializers/content_security_policy.rb` is **entirely commented out**. No CSP header is emitted, which is what makes F10/F11 directly exploitable rather than theoretical. Neither review noted this. | CODE |
| **F29** | `.github/workflows/release.yml` builds and pushes `ghcr.io/…:latest` on **any** `v*` tag, with **no dependency on the `ci.yml` test job**. This is the mechanism by which v1.1.0 was published with a red suite and a critical auth bypass. Fixing it is what stops this recurring. | CODE |
| **F30** | `authentication.rb:52` and `:60` both exempt `controller_name == "feeds"`. There is no `FeedsController` in `app/controllers/`. A dead auth exemption waiting for someone to add a matching controller. | CODE |

---

## Reconciled Defect Register

Reachability is the Stream A/B sort key, per the triage rule: findings reachable
without credentials outrank findings that need a profile. **A non-admin profile
requires no credential** (`FamilyMember#clear_pin_unless_admin` nils the PIN for
members, so `requires_pin?` is false), so "needs a member profile" is *also*
effectively credential-free on a stock install. That is a load-bearing fact for
this table and neither source document accounted for it.

| ID | Defect | Sources | Reach | Stream |
|---|---|---|---|---|
| F1 | All `/onboarding/*` actions anonymous on a configured install → create an admin with a chosen PIN | CL#1 | none | A1 |
| F2 | No `require_admin` on `FamilyMembersController` → rewrite any PIN, delete any member | CL#2, CX, QR | none | A3 |
| F4 | No throttling on either PIN entry path over a 10 000-value keyspace | CL#3, CX | none | A4 |
| F3 | SSRF + unbounded download in `RecipeScraper#fetch_html` | QR, CX | none¹ | A5 |
| F10/F11 | Stored XSS via `innerHTML` in two Stimulus controllers | CL#4, CL#5 | none¹ | A6 |
| F13 | Bidirectional substring pantry-staple matching omits food from the shopping list | QR | any | A7 |
| F6 | Every invalid pantry submission 500s over Turbo | CL#6 | none¹ | A8 |
| F9 | `onboarding#save_pantry` clobbers customized pantry items | CL#9 | none (via F1) | A9 |
| F16a | `verify_pin` is a plaintext `==` (timing side-channel) | QR, CX | n/a | A4 |
| F5 | Month view drops the part of the current week in the next month; **suite is red** | CL#7, CX, QR | any | **T0** |
| F14 | `:role` present in the view, not permitted in the controller | QR | member | A3 (by deletion) |
| F8 | Stored non-GET `return_to` replayed as GET → 404 | CL#8 | member | A11 |
| F29 | Release workflow ships `latest` with no CI gate | new | n/a | A10 |
| F16b | PINs stored plaintext in `family_members.pin` | QR, CX | n/a | B1 |
| F17 | Google service-account JSON plaintext at rest **and** re-rendered into the admin form on every visit | QR, CX | admin | B2 |
| F18 | `docs/architecture.md:43-44` claims encryption that does not exist | CX | n/a | B3 |
| F12 | No CSP header at all | new | n/a | B4 |
| F7 | Slot move destroys the destination outside a transaction | CX | admin | B5 |
| F15 | Explicitly chosen "Other" aisle silently overwritten on every save | CL#10 | member | B6 |
| F19 | `RecipeScraper.new("").send(:categorize_ingredient, …)` encapsulation breach | QR | n/a | B7 |
| F20 | Duplicate calendar test/sync actions in `Admin::HouseholdsController` | QR | n/a | B8 |
| F21 | Four-clause fallback slot lookup at `meal_plan_slots_controller.rb:49` | QR | n/a | B9 |
| F22 | `auto_fulfill_passed_slots!` — unscoped N+1 on 4 hot controller paths | QR | n/a | B10 |
| F23 | 211 queries to save one 15-ingredient recipe | CL#12 | n/a | B11 |
| F24 | Renaming an ingredient strands its old `IngredientAisleMapping` row | CL#11 | n/a | B12 |
| F25 | Full ingredient catalogue serialized once per ingredient row | CL#13 | n/a | B13 |
| F28 | `.gitignore` lacks rules for local cookie/test artifacts | CX | n/a | B14 |
| F26 | `maximum-scale=1` blocks pinch-zoom (WCAG 1.4.4) | CL#14 | n/a | B15 |
| F27 | Millisecond timestamp as `NEW_RECORD` index collides | CL#15 | n/a | B16 |
| F30 | Dead `feeds` auth exemption | new | n/a | A1 |

¹ *Nominally requires a session; in practice requires none, because any anonymous
visitor can assume a PIN-less member profile at `/select_profile`.*

---

## Resolved Disagreements

The reviews propose opposing remedies in five places. One option is carried
forward in each; the other is recorded here and **not** in `tasks/todo.md`.

### D1 — Month boundary: fix the product, not the test

- **QR:** pin the test — `get print_meal_plan_url(@meal_plan, view: "month", month: test_date.strftime("%Y-%m-01"))`.
- **CX / CL#7:** the default month selection is wrong; encode one policy in a shared helper used by both `show` and `print`. CX adds: *"Do not merely pin the test to an explicit month."*
- **Chosen: fix the product.** `@month_date = @week_start.beginning_of_month` is
  duplicated at `meal_plans_controller.rb:26` and `:48`. On 2026-09-01 the
  current plan begins Monday 2026-08-31, so the default month view renders
  August and silently drops the six September days of the *current* week. The
  policy becomes **the month containing the majority of the selected week**
  (≥4 of 7 days), in one private helper called from both actions.
- **Rejected:** pinning the test. It turns the suite green while leaving every
  user's current-week meals invisible in the default month view for six days out
  of every month with a boundary-straddling week. QR's own remedy concedes the
  product behaviour is wrong by having to route around it. Pinning would also
  have to be undone by Task B-anything later, which is churn.
- **Consequence:** the test at `meal_plans_controller_test.rb:81-91` is rewritten
  to assert the new policy, not deleted and not parameterized.

### D2 — Roster mutation: one surface, not two

- **QR:** *"Either permit role modifications for authorized admins **or** route
  roster management exclusively through `Admin::FamilyMembersController`."*
  (Elsewhere QR also says "Retire destructive CRUD actions".)
- **CL#2:** add the missing `require_admin`.
- **CX:** retire roster mutations from the general controller; limit ordinary
  members to their own non-security preferences.
- **Chosen: retire `create`/`update`/`destroy` from `FamilyMembersController`
  entirely.** `index` and `switch` stay; the roster UI links to
  `Admin::FamilyMembersController`, which already has the correct gating.
  Ordinary members keep self-service editing through `PreferencesController`,
  which already models the right shape (`preference_params` withholds `:pin`
  from non-admins at `preferences_controller.rb:31-35`).
- **Rejected:** adding `require_admin` and permitting `:role` in place. That
  keeps two parallel roster-mutation surfaces, which have now drifted out of
  sync **twice in one release** — once by omitting `require_admin` (F2) and once
  by omitting `:role` (F14). Patching both symptoms leaves the mechanism that
  produced them.
- **Consequence:** **F14 is fixed by deletion, not by permitting `:role`.** The
  role select at `family_members/index.html.erb:108-109` is removed along with
  the form it sits in. Do not add `:role` to `family_member_params`.

### D3 — PIN storage: `secure_compare` now, digest next release

- **QR:** `ActiveSupport::SecurityUtils.secure_compare` **or** `has_secure_password`.
- **CX:** store digests, constant-time verify, migrate existing plaintext.
- **Chosen (user decision):** Stream A ships `secure_compare` only — code-only,
  no migration. Stream B (**B1**) adds `pin_digest`, backfills, verifies, and
  drops `pin`.
- **Rejected for the patch:** shipping the schema migration in `v1.1.1`. The
  out-of-band patch goes to people already running the ghcr image against live
  SQLite volumes; an emergency patch is the worst moment to require a migration
  with a non-trivial rollback story.
- **Note:** `secure_compare` on unequal-length strings raises unless wrapped;
  use `ActiveSupport::SecurityUtils.fixed_length_secure_compare` on digests, or
  guard length first. B1 makes this moot.

### D4 — SSRF: egress filtering, not a literal denylist

- **QR:** reject `parsed.host.in?(%w[localhost 127.0.0.1 169.254.169.254])`.
- **CX:** dedicated HTTP client; HTTP(S) only; resolve and reject private,
  loopback, link-local, multicast and reserved addresses **before every request
  and every redirect**; cap redirects and bytes.
- **Chosen: CX's.**
- **Rejected:** QR's three-literal denylist. It misses `10.0.0.0/8`,
  `172.16.0.0/12`, `192.168.0.0/16`, the rest of `127.0.0.0/8`, `::1`,
  `fc00::/7`, IPv4-mapped IPv6, `0.0.0.0`, decimal/octal IPv4 spellings, any
  hostname that *resolves* into private space, and redirect-to-private. It also
  leaves `ftp://` open — verified above, `URI::FTP` responds to `#open`. A
  string denylist on a value the attacker fully controls is not a boundary.
- **Not carried forward:** the local-file-read claim in both documents. See
  Verification Log item 1. The fix is the same either way; the plan just does
  not assert something that is false.

### D5 — Staple matching: exact normalized match, not word boundaries

- **QR:** `n == s || n.match?(/\b#{Regexp.escape(s)}\b/)`.
- **Chosen: exact match on a normalized name** — downcase, strip, collapse
  whitespace, singularize both sides. No substring logic in either direction.
- **Rejected:** the word-boundary regex. Measured against the stock staple list,
  it still marks Peanut butter, Salted butter, Rice vinegar, Rice noodles, Pasta
  sauce, Garlic bread, Green onions and Brown rice as already-in-pantry — 7 of
  the 10 real false positives survive (table in Verification Log item 2).
- **Rationale:** the two error directions are not symmetric. A false negative
  puts an extra line on the shopping list — the user sees it and ignores it. A
  false positive means an ingredient is silently *not bought* and is discovered
  at dinner. Under asymmetry that steep, prefer under-matching. Singularization
  keeps the useful cases ("Egg" ↔ "Eggs", "Onion" ↔ "Onions") without reopening
  substring matching.
- **Accepted cost:** "Kosher salt" no longer matches the "Salt" staple. That is
  the correct trade under the reasoning above, and a user who wants it can add
  "Kosher salt" to their pantry. If aliasing is wanted later it belongs in an
  explicit alias table, not in fuzzy matching.

---

## Architecture Decisions

1. **Two streams, one branch.** Both stream off `master` (which *is* `v1.1.0` —
   HEAD is the release commit, so there is no divergence to merge). Stream A
   lands first and is tagged `v1.1.1`; `release.yml` builds and moves `latest`
   on the tag. Stream B continues on the same branch toward `v1.2.0`.
2. **Stream A carries no migration.** Non-negotiable. It is the property that
   makes the patch safe to push to unattended home installs on SQLite volumes.
   Any task that needs a schema change belongs in Stream B by construction.
3. **Authorization is fixed at the routing layer, not per-action.** F1 and F2
   are both "an action that should never have been reachable was reachable".
   Removing routes and actions is verifiable by reading `config/routes.rb`;
   `before_action` coverage is verifiable only by auditing every action, which
   is how this release shipped two gaps.
4. **One month-selection policy, one helper.** The duplication between `show`
   and `print` is the reason the bug has two symptoms.
5. **PIN-less member profiles are retained** (user decision), preserving the
   v1.1.0 "zero PIN friction / 1-tap switching" decision recorded in
   `tasks/archive/v1.1.0-plan.md`. The plan therefore does **not** treat "has a
   member session" as a trust boundary anywhere; it is equivalent to anonymous.
   Every Stream A authorization task is written against that assumption.
6. **The CI gate is part of the remediation, not process hygiene.** F29 is the
   direct cause of a critical auth bypass reaching `ghcr.io/…:latest`. Without
   A10 the same class of release can happen again the day this plan closes.

---

## Dependency Graph

```
T0  month-selection helper + green baseline
 │   (only task permitted to start from a red suite)
 │
 ├── A1  onboarding lockdown ──────┐
 │                                  │
 ├── A2  session-fixture test helper┤   (shared test scaffolding
 │                                  │    used by A3/A4/A5/A6)
 ├── A3  roster consolidation ──────┤
 ├── A4  PIN throttle + secure_compare
 ├── A5  SSRF egress guard ─────────┤
 ├── A6  XSS escaping               │
 ├── A7  staple exact matching      │
 ├── A8  pantry turbo_stream format │
 ├── A9  save_pantry create-only    │
 ├── A11 GET-only return_to ────────┘
 │
 └── A10 CI gate on release.yml  ← must land before the v1.1.1 tag
      │
      ▼
   ══ CHECKPOINT: v1.1.1 released ══
      │
      ├── B1  pin_digest migration ── depends on A4 (verify path)
      ├── B2  encrypt google_service_account_json ─┐
      │                                             ├── B3 architecture.md
      ├── B4  CSP  ← depends on A6 (escape first)  ─┘
      ├── B5  transactional slot move ──┐
      ├── B9  slot lookup simplification┘  (same action; B5 then B9)
      ├── B6  Other-aisle preservation ──┐
      ├── B7  IngredientClassifier ──────┼── B11 callback query reduction
      ├── B12 rename re-sync ────────────┘   (B7 first: shared extraction)
      ├── B8  admin calendar dedup
      ├── B10 auto_fulfill batch update
      ├── B13 hoist catalogue JSON  ← depends on B7 (same call site)
      ├── B14 .gitignore
      ├── B15 viewport
      └── B16 monotonic row index
```

---

## UI Consistency Pass (outside Stream A/B)

Follow-up to the A6 visual review, done at the user's direction. Presentation
only — no controller, model or behaviour changes, and it belongs to neither
stream. Recorded here so the decisions are not re-litigated.

**Changes:** the tag picker's permanent suggestion chips removed (the dropdown
already listed every unselected tag) and its menu narrowed from full field width
to `w-72`; ingredient name and unit menus widened with `overflow-x-hidden` (their
horizontal scrollbar came from `overflow-y-auto` computing `overflow-x` from
`visible` to `auto`); a `themed-scrollbar` utility applied to every scrollable
menu in the app; the slot modal's six fields unified on the recipe trigger's
treatment (2xl radius, 2px border, matching hover/focus); `themed-select` chevron
on all 8 selects; and `color-scheme` declared on `:root`/`.dark`, which is what
makes the browser paint date and time picker popups in the app's theme.

### Decision: native controls stay native

The popup a `<select>` opens is drawn by the platform. Its **colours** are
reachable — `option`, `option:checked` and `option:disabled` now carry the app's
palette — but its **shape** is not, and no CSS reaches it. Date and time picker
panels are the same.

Rounding those popups means giving up a real `<select>`, and with it keyboard
navigation, type-ahead, screen-reader semantics, and the native wheel/sheet iOS
and Android render — which is the better interaction on the kitchen tablet this
app targets. Not worth trading for a border radius on a transient popup.
Revisit when CSS `appearance: base-select` has support beyond Chromium 135+;
it keeps a real `<select>` *and* allows a styled popup.

### Decision: the recipe picker stays custom

Audit of every popup in the app:

| Kind | Controls | Native? |
|---|---|---|
| `<select>` | role ×3, meal type ×2, assigned cook ×2, aisle category | yes |
| date/time inputs | 6 | yes |
| Action/nav menus | profile switcher, theme toggle, recipe sort/filter, recipe card actions, onboarding select-all | **no native equivalent exists** — HTML has no menu control |
| Comboboxes & pickers | tag picker (multi-value + create), ingredient name/unit (free text + suggestions), pantry icon grid (SVG) | **cannot be native** without removing a capability |
| Single-choice list | slot modal recipe picker | could be native; **deliberately is not** |

The recipe picker is the one custom control a `<select>` could replace. It stays
custom because it renders a thumbnail, cook time and tags per row — `<option>` is
text-only — and it is the only place a recipe is chosen without already knowing
its name. This is a deliberate exception, not an oversight.

---

## Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| A3 removes routes the UI still links to | High — dead links in the roster view | A3's acceptance criteria include grepping every `family_members_path`/`family_member_path` reference; the roster view links to `admin_family_members_path` instead |
| A1 breaks first-boot onboarding for genuinely new installs | High — new users cannot set up | A1 must add a test for the *unconfigured* path (`Household.none?`) alongside the configured-install lockout. Both directions, same task |
| A5's egress filter breaks legitimate recipe imports | Medium — core feature regression | Filter is deny-by-address, not allow-by-host; add a test importing from a public IP fixture. Time-of-check/time-of-use is handled by resolving and pinning the address, not by re-resolving |
| A4 throttling locks a family out of their own admin profile | Medium | Per-IP *and* per-profile keys with a short window and backoff, not a hard lockout; document the reset path |
| D5's exact matching over-reports staples on shopping lists | Low — extra lines on a list | Explicitly accepted; see D5 rationale. Ships with the table in the test as documentation |
| B1's digest migration fails on a live SQLite volume | High — locked-out admins | Separated into its own release, with an explicit backup step and an additive-then-drop two-phase migration, not a rename |
| Stream A grows and delays the patch | Medium — critical bugs stay live | A is capped at 11 tasks, all S or XS, none requiring a migration. Anything that grows moves to B |
| The XSS fix is incomplete without a CSP | Medium | A6 escapes at the sink (complete on its own); B4 adds CSP as defense in depth, ordered after A6 so the inline theme script's nonce work does not block the patch |

---

## Open Questions

- **F28 / cookie artifact:** `cookies.txt` is absent from this worktree but CX
  observed it (mode `0644`) in the primary checkout. Whoever runs B14 should
  confirm whether it still exists there; if so it needs shredding and the
  session it holds needs invalidating. Not blocking Stream A.
- **F17 / credential rotation:** if any live deployment has a Google service
  account key stored, encrypting at rest (B2) does not undo the fact that it was
  rendered into HTML on every visit to the admin calendar page. B2's release
  notes should tell operators to rotate the key, not just upgrade.
- **v1.1.1 disclosure:** the patch fixes a remote, unauthenticated privilege
  escalation in a publicly published image. Whether that warrants a GitHub
  security advisory alongside the release notes is the maintainer's call, not a
  task in this plan.
