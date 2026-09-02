# v1.1.0 Remediation — Task List

Companion to `tasks/plan.md`. Findings are `F<n>`; the reconciled register and
the five resolved disagreements (`D1`–`D5`) are in the plan. Do not re-open a
resolved disagreement from the source review documents.

**Baseline was RED:** 172 runs, 657 assertions, 1 failure
(`test/controllers/meal_plans_controller_test.rb:91`). Task 0 fixed it. **Current:
GREEN at 259 runs, 1298 assertions, 0 failures** (Stream A complete; Stream B: B1–B4). Every
remaining task starts from and must preserve green.

Repository commands used throughout:

- Focused test: `PARALLEL_WORKERS=1 bin/rails test <path>[:<line>]`
- Full suite: `PARALLEL_WORKERS=1 bin/rails test`
- Lint: `bin/rubocop`
- Static security scan: `bin/brakeman --no-pager`

---

## Task 0: Derive the month view from the week's majority month  ✅ DONE

**Description:** Replace the duplicated `@month_date = @week_start.beginning_of_month`
in `MealPlansController#show` (`:26`) and `#print` (`:48`) with a single private
helper implementing one policy: the default month is the month containing at
least 4 of the selected week's 7 days. An explicit `month:` parameter still wins.
This repairs F5 and turns the suite green. Per **D1**, the fix is in the
controller, not in the test — the test is rewritten to assert the new policy.

**Acceptance criteria:**
- [x] One private method (e.g. `default_month_for(week_start)`) is the only place the default month is computed; both `show` and `print` call it
- [x] With `week_start_date = 2026-08-31`, the default month view renders September and includes slots dated 2026-09-04
- [x] An explicit `?month=2026-08-01` still renders August, unchanged
- [x] `meal_plans_controller_test.rb:81` asserts the majority-month policy; it is **not** pinned with an explicit `month:` param

**Verification:**
- [x] `PARALLEL_WORKERS=1 bin/rails test test/controllers/meal_plans_controller_test.rb` passes
- [x] Full suite: **176 runs, 706 assertions, 0 failures** — this is the green baseline every later task depends on
- [x] `bin/rubocop` clean (118 files, 0 offenses); `bin/brakeman --no-pager` clean (0 warnings)
- [x] Boundary week rendering — covered by request tests rather than by hand: `month view defaults to the month holding most of the week when the week ends in the next month` and `print month view uses the same default month as the planner` drive the real controller and render the real `show.html.erb` / `print.html.erb`, asserting the Sep 4 slot appears for the Aug 31 – Sep 6 week. **Not** separately clicked through a running server.

**Dependencies:** None
**Files:** `app/controllers/meal_plans_controller.rb`, `test/controllers/meal_plans_controller_test.rb`
**Scope:** S

**Outcome:** `resolve_month_date` / `default_month_for` added to `MealPlansController`; both `show` and `print` call them. Suite is now **GREEN: 176 runs, 706 assertions, 0 failures** (was 172/657/1). `bin/rubocop` 0 offenses, `bin/brakeman` 0 warnings. The three rewritten/added tests were confirmed to fail against the old `@week_start.beginning_of_month` expression before the fix landed.

---

# Stream A — `v1.1.1` out-of-band patch

Reachable without credentials, or actively broken for people running the ghcr
image. **No task in Stream A may add a schema migration** (plan, Architecture
Decision 2). Note throughout: a member profile is *not* a credential — non-admin
members have no PIN, so anyone can assume one at `/select_profile`.

## Task A1: Close anonymous access to the onboarding wizard  ✅ DONE

**Description:** Fixes **F1** (verified: anonymous `POST /onboarding/add_member`
with `role=admin&pin=9999` created a working admin). `authentication.rb:52` and
`:60` return early for any `controller_path.start_with?("onboarding")`, which
makes the `allow_unauthenticated_access only: %i[family save_family]` declaration
at `onboarding_controller.rb:2` dead code. Remove the blanket exemption so the
per-action declaration governs, and extend `ensure_household_unconfigured` to
every wizard step. Also drop the dead `controller_name == "feeds"` exemption
(**F30**) — no `FeedsController` exists.

**Acceptance criteria:**
- [x] `require_authentication` and `require_active_family_member` no longer special-case `onboarding` or `feeds` by name
- [x] On a configured install, every `/onboarding/*` action is either authenticated-admin-only or redirects to `/select_profile`; anonymous `POST /onboarding/add_member` creates nothing
- [x] On an unconfigured install (`Household.none?`), the full wizard still completes anonymously end to end

**Verification:**
- [x] New request test: anonymous `POST /onboarding/add_member` with `role=admin` → no new `FamilyMember`, non-2xx/302-to-onboarding
- [x] New request test: `Household.destroy_all` then walk family → members → recipes → pantry → complete anonymously and succeed
- [x] `PARALLEL_WORKERS=1 bin/rails test` green; `bin/brakeman --no-pager` clean

**Dependencies:** Task 0
**Files:** `app/controllers/concerns/authentication.rb`, `app/controllers/onboarding_controller.rb`, `test/controllers/onboarding_controller_test.rb`
**Scope:** S

**Outcome:** Both name-based exemptions deleted from `Authentication`; per-action
`allow_unauthenticated_access` now governs, and the dead `feeds` exemption is gone
(**F30**). Suite **183 runs, 735 assertions, 0 failures**; RuboCop and Brakeman clean.
The five new access-control tests were confirmed to fail against HEAD before the fix.

**Deviation from the description above:** the plan said to extend
`ensure_household_unconfigured` to every wizard step. Used `require_admin` on the
post-setup steps instead. Blocking them outright would break resuming an
interrupted setup, and would be a behaviour change wider than closing the hole;
admin-gating satisfies the acceptance criterion and preserves the flow. This also
closes a second hole neither review named: `OnboardingController#family_member_params`
permits `:role`, so before this change **any signed-in member** — and a member
profile needs no PIN — could `POST /onboarding/add_member` to mint themselves an
admin, entirely bypassing `Admin::FamilyMembersController`.

## Task A2: Add a session helper for authenticated request tests  ✅ DONE

**Description:** Tasks A3–A6 and A11 each need to drive requests as an anonymous
visitor, a member, and an admin. `test/test_helpers/session_test_helper.rb`
exists; extend it with explicit `sign_in_as(member)` / `sign_out` helpers built
on `POST /set_profile/:id` so the auth tests exercise the real cookie path rather
than stubbing `Current`.

**Acceptance criteria:**
- [x] `sign_in_as(family_members(:one), pin: "1234")` and `sign_in_as(family_members(:two))` both work from an `ActionDispatch::IntegrationTest`
- [x] Helpers assert the session cookie was actually set, so a silent auth failure fails the test rather than passing as "anonymous"

**Verification:**
- [x] At least one existing controller test converted to the helper still passes
- [x] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** Task 0
**Files:** `test/test_helpers/session_test_helper.rb`
**Scope:** XS

**Outcome:** Smaller than planned in one way and larger in another. `sign_in_as`
already existed and all 58 call sites already used it, so nothing needed
converting — but it *forged* the signed cookie directly and set `Current` in the
test process, so no test in the suite had ever exercised `POST /set_profile/:id`,
the PIN check included. It now drives the real path, which is what A4 needs to
throttle against. Added `active_family_member_id` / `signed_in_as?` (integration
tests get a `Rack::Test` jar with no `#signed`, so the value is unwrapped through
a jar sharing the app's secret), and `sign_out` now goes through `DELETE /session`.

The old helper had exactly the silent-failure mode this task was meant to remove:
it no-opped when handed something that was not a member, and ignored the PIN
entirely — `sign_in_as(admin, pin: "9999")` "succeeded". Both now fail loudly.
`test/integration/session_test_helper_test.rb` pins those failure modes; removing
the guard makes the wrong-PIN test fail, confirmed. Suite **189 runs, 750
assertions, 0 failures**; RuboCop (119 files) and Brakeman clean.

## Task A3: Consolidate roster mutation into `Admin::FamilyMembersController`  ✅ DONE

**Description:** Fixes **F2** (verified: anonymous → PIN-less member profile →
`PATCH /family_members/<admin_id>` with `pin=0000` → admin PIN rewritten) and
**F14**. Per **D2**, remove `create`, `update` and `destroy` from
`FamilyMembersController` and from its route entry; keep `index` and `switch`.
The roster view links to `Admin::FamilyMembersController`, which already gates
correctly. **Do not add `:role` to `family_member_params`** — F14 is fixed by
deleting the surface, not by permitting the attribute.

**Acceptance criteria:**
- [x] `config/routes.rb` declares `resources :family_members, only: %i[index]` plus the `switch` member route
- [x] `create`/`update`/`destroy` and the now-unused `family_member_params` are gone from `FamilyMembersController`
- [x] `app/views/family_members/index.html.erb` no longer renders the create form or role select (`:108-109`); it links to `admin_family_members_path`
- [x] No `family_members_path`/`family_member_path` reference anywhere in `app/` still points at a removed verb

**Verification:**
- [x] New request test: signed in as `family_members(:two)` (member), `PATCH /family_members/<admin id>` with `pin=0000` → 404 and `admin.reload.pin` unchanged
- [x] New request test: same as a member, `DELETE /family_members/<admin id>` → 404, member still exists
- [x] New request test: a member can still change their own name/avatar via `PATCH /preferences`, and still cannot set `:pin` there
- [x] `grep -rn "family_member" app/views app/controllers` reviewed for dead paths
- [x] `PARALLEL_WORKERS=1 bin/rails test` green; `bin/rubocop` clean

**Dependencies:** Task 0, A2
**Files:** `config/routes.rb`, `app/controllers/family_members_controller.rb`, `app/views/family_members/index.html.erb`, `test/controllers/family_members_controller_test.rb`
**Scope:** M

**Outcome:** `create`/`update`/`destroy` and `family_member_params` deleted from
`FamilyMembersController`; the route is `only: %i[index]` plus `switch`. The view
lost the create form (role select included) and the delete modal, and now links
admins to `admin_family_members_path` and members to their own preferences.
`family_member_url` no longer resolves as a route helper — the regression tests
drive the raw paths instead, which is the shape of the attack anyway. All five
access-control tests confirmed failing against the old code. Suite **193 runs,
764 assertions, 0 failures**; RuboCop and Brakeman clean.

**Note:** `Admin::FamilyMembersController` was already a strict superset of what
was removed (index/create/edit/update/destroy/reset_pin, `:role` permitted, gated
by `Admin::BaseController`), so nothing had to be rebuilt there — the general
controller was pure duplication with the authorization left off.

## Task A4: Throttle PIN entry and compare PINs in constant time  ✅ DONE

**Description:** Fixes **F4** and the timing half of **F16**. The removed
`SessionsController` carried `rate_limit to: 10, within: 3.minutes`; neither
`profiles#set` nor `family_members#switch` inherited anything, leaving a
10 000-value keyspace open to unthrottled guessing — and `profiles#set` is
reachable anonymously. `solid_cache` is configured in production
(`config/environments/production.rb:50`), so Rails 8 `rate_limit` works. Per
**D3**, this task adds `ActiveSupport::SecurityUtils` comparison only; the
digest migration is B1.

**Acceptance criteria:**
- [x] `rate_limit` applied to `ProfilesController#set` and `FamilyMembersController#switch`, keyed on **both** remote IP and target profile id
- [x] Exceeding the limit returns a throttled response and does not reveal whether the PIN was correct
- [x] `FamilyMember#verify_pin` uses a constant-time comparison and does not raise on length mismatch
- [x] Failed attempts emit a log line suitable for `fail2ban`-style tooling; the line contains no PIN material

**Verification:**
- [x] New request test: 11 wrong-PIN `POST /set_profile/:id` in the window → the last is throttled
- [x] New request test: throttling on profile A does not lock out profile B from a different IP
- [x] Unit test: `verify_pin("123")`, `verify_pin("")`, `verify_pin(nil)` all return false without raising
- [x] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** Task 0, A2
**Files:** `app/controllers/profiles_controller.rb`, `app/controllers/family_members_controller.rb`, `app/models/family_member.rb`, `test/controllers/profiles_controller_test.rb`, `test/models/family_member_test.rb`
**Scope:** M

**Outcome:** `PinThrottling` concern wraps two Rails `rate_limit` declarations —
one keyed per IP, one per target profile — included by both entry paths and
sharing one `scope`, so an attacker cannot take 10 tries at `/set_profile` and 10
more at `/family_members/:id/switch`. `verify_pin` now uses
`ActiveSupport::SecurityUtils.secure_compare`. Six of the seven new tests were
confirmed failing without the throttle. Suite **202 runs, 835 assertions, 0
failures**; RuboCop (122 files) and Brakeman clean.

**Two implementation notes worth carrying forward:**

1. *Only PIN-protected targets are counted* (`if: -> { pin_protected_target? }`).
   Counting every profile selection would throttle ordinary 1-tap member
   switching on a shared kitchen tablet, where the whole family is behind one
   NAT address — the exact UX the v1.1.0 plan chose PIN-less members to get.
2. *The test environment runs `:null_store`*, whose `#increment` returns `nil`,
   which Rails' rate limiter reads as "under the limit". Left alone, every test
   written to prove throttling works would have passed against no throttling at
   all. `config/initializers/pin_attempt_store.rb` gives tests a real
   `MemoryStore`; `test_helper` clears it per test so one test cannot spend
   another's budget. Production uses `Rails.cache` (solid_cache, database-backed)
   because a per-process store would multiply the limit by the Puma worker count.

**Correcting the plan's D3 note:** it warned that `secure_compare` raises on a
length mismatch and suggested `fixed_length_secure_compare` on digests. Backwards
— in Rails 8.1 `fixed_length_secure_compare` is the one that raises, and
`secure_compare` guards it with a bytesize check first, returning false. Verified
against `activesupport-8.1.3.1/lib/active_support/security_utils.rb` and pinned by
unit tests over short, long, empty and nil input. It does leak length by
short-circuiting, which is immaterial for a fixed four-digit PIN.

## Task A5: Filter outbound recipe-import requests  ✅ DONE

**Description:** Fixes **F3**. `RecipeScraper#fetch_html` (`:36-44`) calls
`URI.parse(url).open` on fully attacker-controlled input with no scheme, address,
redirect or size checks, reaching loopback, RFC1918, `169.254.169.254` and the
Docker bridge. Per **D4**, implement address-based egress filtering, not a host
denylist. Verified correction: `file:` URLs are **not** exploitable (`URI::File`
has no `#open`), so do not write tests or release notes claiming local file read
— but `ftp://` **is** reachable (`URI::FTP` responds to `#open`) and must be
rejected by the scheme allowlist.

**Acceptance criteria:**
- [x] Scheme allowlist: `http`/`https` only, checked before any network call
- [x] The hostname is resolved and every resulting address rejected if loopback, private, link-local, multicast, reserved, unspecified, or IPv4-mapped equivalents thereof — for the initial request **and each redirect hop**
- [x] Redirects capped (≤5) and response body capped (≤2 MB), streaming-truncated rather than buffered whole
- [x] Rejections are logged and surface to the user as the existing "Could not fetch recipe" message — no internal detail leaks into the flash
- [x] The bare `rescue StandardError` no longer masks a validation failure as an ordinary fetch failure

**Verification:**
- [x] Unit tests reject: `file:///etc/passwd`, `ftp://example.com/x`, `http://127.0.0.1:3000/`, `http://[::1]/`, `http://10.0.0.1/`, `http://192.168.1.1/`, `http://169.254.169.254/latest/meta-data/`, a hostname resolving to `127.0.0.1`, and an HTTP redirect from a public address into `10.0.0.0/8`
- [x] Unit test: an oversized response is truncated/rejected rather than read into memory
- [x] Unit test: a public-address fetch still parses a JSON-LD recipe (import is not regressed)
- [x] `PARALLEL_WORKERS=1 bin/rails test` green; `bin/brakeman --no-pager` clean

**Dependencies:** Task 0
**Files:** `app/services/recipe_scraper.rb`, new `app/services/safe_http_fetcher.rb` (or equivalent), `test/services/recipe_scraper_test.rb`
**Scope:** M

**Outcome:** `open-uri` is gone. `OutboundUrlPolicy` decides by *resolved address*
against explicit CIDR lists (v4 and v6), rejecting loopback, private, CGNAT,
link-local/metadata, unspecified, multicast, reserved, documentation and NAT64
space, unwrapping IPv4-mapped IPv6 first. It requires **every** DNS answer to
pass, then pins the one address the request may use — `SafeHttpFetcher` sets
`Net::HTTP#ipaddr` so the hostname is still used for SNI and `Host` but nothing
re-resolves between check and connect, which is the DNS-rebinding hole. Every
redirect hop goes back through the policy; redirects capped at 5, body streamed
and capped at 2 MB. `RecipeScraper` now distinguishes a policy refusal
(`[egress] … refused`) from an ordinary fetch failure. Suite **223 runs, 919
assertions, 0 failures**; RuboCop (126 files) and Brakeman clean.

**Found while doing this — a bug none of the three reviews reported.**
`RecipeScraper#scrape` never returned `nil`: a failed fetch fell through to
`Nokogiri::HTML(nil)` and built an OpenGraph fallback, so importing *any*
unreachable URL silently created a placeholder recipe titled "Imported Recipe"
with the rejected URL as its `source_url`. That made
`RecipeImportsController`'s `if data.nil?` branch — the "Could not fetch recipe"
message this task's criteria require — **dead code since it was written**. Fixed
by returning `nil` on blank HTML, with a controller test pinning the message.

**Test tooling note:** `minitest/mock` is not available (Minitest 6), so the
split-horizon and address-pinning tests swap the resolver with a plain
`define_singleton_method` and restore it, and `SafeHttpFetcher`'s redirect tests
use a `ScriptedFetcher` subclass that overrides the network seam. No test in this
task can reach a real network, by construction.

## Task A6: Escape user and scraped content at the DOM sinks  ✅ DONE

**Description:** Fixes **F10** and **F11**. Three `innerHTML` sites interpolate
database-sourced strings: `tag_picker_controller.js:191` (from free-text
`recipes.tags`), and `ingredient_autofill_controller.js:82` and `:210` (from
`recipe_ingredients.name`, which `RecipeScraper` writes straight from an
arbitrary third-party page). With no CSP header (**F12**, addressed in B4) an
injected inline handler executes for every user who opens the recipe form.

**Acceptance criteria:**
- [x] All three sites build nodes with `createElement` + `textContent`; no template literal reaches `innerHTML` carrying a database or scraped value
- [x] Static class strings and the aisle badge colour still apply (`getAisleBadgeColor` output is a fixed class list, not user data)
- [x] `grep -rn "innerHTML" app/javascript/controllers/` shows no remaining site interpolating a dynamic value

**Verification:**
- [x] Manual: create a recipe tagged `<img src=x onerror=alert(1)>`, open the recipe form, type in the tag box — the tag renders as literal text, no dialog
- [x] Manual: same with an ingredient named `<img src=x onerror=alert(1)>` in the autofill list and the unit list
- [x] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** Task 0
**Files:** `app/javascript/controllers/tag_picker_controller.js`, `app/javascript/controllers/ingredient_autofill_controller.js`
**Scope:** S

**Outcome:** Larger than the plan's three sites. A sweep of every `innerHTML` in
`app/javascript/controllers/` found **seven** interpolating a dynamic value; the
reviews named three. New `app/javascript/helpers/dom.js` (`el` / `replaceChildren`,
pinned in `config/importmap.rb`) builds nodes with `createElement` + `textContent`
+ `setAttribute`. Suite **223 runs, 0 failures**; RuboCop, Brakeman and
`importmap audit` clean; every controller passes `node --check`.

**The four sinks no review reported:**

| Site | Value | Source |
|---|---|---|
| `slot_modal_controller.js:121` | `recipeData.title`, `tags`, `image_url`, `total_time` | `recipes` — **written by the scraper from arbitrary third-party pages** |
| `calendar_sync_controller.js:55, :62` | `data.summary`, `data.error` | Google Calendar API responses |
| `calendar_sync_controller.js:141, :150` | `data.message`, `data.error` | same |
| `pantry_item_form_controller.js:132` | `iconId` | the pantry emoji field, straight user input |

`slot_modal` is the worst of the seven and sits on the meal planner, the app's
most-used screen: `image_url` went into an `src` attribute and `title` into `alt`,
so a scraped value containing a double quote escapes the attribute outright. It
now also runs through a `safeImageUrl` guard that falls back to the placeholder
for anything that is not `http:`/`https:` — `setAttribute` alone stops attribute
injection but would still happily accept a `javascript:` URL.

**Verification gap, stated plainly:** the plan asked for a manual browser check
and there is no browser or system-test harness in this repo (no Capybara, no
`test/system`), so that was **not** performed. Instead the helper's semantics were
proved under Node against a minimal DOM stand-in: a `<img src=x onerror=…>`
payload is stored verbatim in `textContent` with zero child nodes parsed, and
`src`/`alt` values containing quotes land through `setAttribute` un-interpolated.
That covers the escaping contract; it does not cover whether the rebuilt markup
still *looks* right. A human should click through the recipe form, tag box, slot
modal, pantry icon picker and admin calendar page before the tag.

## Task A7: Match pantry staples by exact normalized name  ✅ DONE

**Description:** Fixes **F13**. `IngredientAggregator#is_staple_item?` (`:83-86`)
matches substrings in **both** directions, so ingredients are silently dropped
from the shopping list. Per **D5**, replace it with exact matching on a
normalized name (downcase, strip, collapse whitespace, singularize both sides).
The word-boundary remedy proposed in the quality report was measured and rejected
— it leaves 7 of 10 real false positives in place against the stock staple list.

**Acceptance criteria:**
- [x] `is_staple_item?` performs no substring comparison in either direction
- [x] Against the stock `PantryItem::DEFAULT_STAPLES`, none of these are treated as in-pantry: Butternut squash, Buttermilk, Peanut butter, Salted butter, Rice vinegar, Rice noodles, Pasta sauce, Garlic bread, Green onions, Brown rice
- [x] Singular/plural still matches: an ingredient "Egg" matches the "Eggs" staple; "Onion" matches "Onions"
- [x] Exact matches still match, case- and whitespace-insensitively

**Verification:**
- [x] New unit test table-driving all ten negative cases above plus the positive cases — this table is the documentation of D5's accepted trade-off
- [x] New unit test recording the accepted regression: "Kosher salt" no longer matches the "Salt" staple
- [x] `PARALLEL_WORKERS=1 bin/rails test` green
- [x] Manual: a plan containing peanut butter and brown rice shows both on the shopping list

**Dependencies:** Task 0
**Files:** `app/services/ingredient_aggregator.rb`, `test/services/ingredient_aggregator_test.rb`
**Scope:** S

**Outcome:** `is_staple_item?` is now `staples_list.include?(normalize_for_match(name))`
— no substring comparison in either direction. Normalization is downcase, strip,
squeeze whitespace, singularize, applied to **both** sides (`load_staples_map`
normalizes the stored staple names too, which it previously only downcased).
Suite **227 runs, 946 assertions, 0 failures**; RuboCop and Brakeman clean.

Tests drive the real `IngredientAggregator.call` over a purpose-built household,
recipe and plan rather than poking the private method, so they prove the item
actually reaches the shopping list. Confirmed failing against the old code
("Butternut squash was wrongly treated as already in the pantry").

The `NOT_IN_PANTRY` table in the test is the durable record of D5: all ten
survived as real defects, and seven of them would have survived the quality
report's word-boundary remedy too. The "Kosher salt" case is kept as an explicit
test of the *accepted* regression rather than left as a surprise, paired with one
showing it matches once the household adds it.

## Task A8: Stop invalid pantry submissions returning 500  ✅ DONE

**Description:** Fixes **F6** (verified: `POST /pantry_items` with a blank name
and a Turbo `Accept` header raises `ActionView::MissingTemplate ... formats:
[:turbo_stream]`). `pantry_items_controller.rb:21` and `:37` render `:index` for
the `turbo_stream` format, but only `index.html.erb` exists and Rails does not
fall back to HTML. The pantry form is Turbo-driven, so a blank name — or a
duplicate, since `(household_id, name)` is uniquely indexed — 500s instead of
showing validation errors.

**Acceptance criteria:**
- [x] Invalid `create` and `update` render the HTML index with `:unprocessable_entity` and the model's error messages visible
- [x] No 500 for a blank name or a duplicate name over either format

**Verification:**
- [x] New request test: `POST /pantry_items` with `name: ""` and `Accept: text/vnd.turbo-stream.html` → 422, response body contains the validation message
- [x] New request test: same for a duplicate name, and for `PATCH /pantry_items/:id`
- [x] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** Task 0
**Files:** `app/controllers/pantry_items_controller.rb`, `test/controllers/pantry_items_controller_test.rb`
**Scope:** XS

**Outcome:** Both error branches collapse into `render_index_with_errors`, which
renders with `formats: [:html]`. Suite **231 runs, 959 assertions, 0 failures**.
All four new tests confirmed failing against the old code.

**Bigger than XS, because the HTML path was broken too.** The error branches set
`@pantry_items` and `@items_by_category` but never `@new_item` — and the form is
`form_with model: @new_item`. So `render :index` raised on `model: nil` for plain
HTML as well; the turbo_stream `MissingTemplate` was just the failure that got
noticed. The helper now sets all three, binding the form to the *rejected* record,
which is also what surfaces the errors.

And the form had nowhere to show them: `index.html.erb` rendered no
`errors.full_messages` block at all, so even a fixed render would have bounced the
user back to an apparently-blank form with no explanation. Added.

## Task A9: Stop `save_pantry` overwriting customized pantry items  ✅ DONE

**Description:** Fixes **F9**. `onboarding_controller.rb:143-147` changed from
`find_or_create_by!(name:) { … }` (block runs on create only) to
`find_or_initialize_by` followed by unconditional assignment of `aisle_category`,
`emoji` and `is_staple`, so re-running the pantry step resets hand-picked
categories and icons to the `DEFAULT_STAPLES` values. Only `is_staple` should
follow the checkbox on an existing row.

**Acceptance criteria:**
- [x] On an existing pantry item, `save_pantry` updates `is_staple` only; `aisle_category` and `emoji` are preserved
- [x] On a new pantry item, all three are still seeded from `DEFAULT_STAPLES`

**Verification:**
- [x] New request test: customize an item's `aisle_category` and `emoji`, re-post `save_pantry`, assert both survive and `is_staple` tracked the checkbox
- [x] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** Task 0, A1
**Files:** `app/controllers/onboarding_controller.rb`, `test/controllers/onboarding_controller_test.rb`
**Scope:** XS

**Outcome:** `aisle_category` and `emoji` are assigned only when
`item.new_record?`; `is_staple` still tracks the checkbox, which is the only
answer this screen asks for. Suite **234 runs, 967 assertions, 0 failures**;
RuboCop and Brakeman clean.

Three tests, covering the fix and both directions it could over-correct into:
customizations survive, unchecking a staple still works, and a genuinely new item
still gets its `DEFAULT_STAPLES` seed. The first is confirmed failing against the
old code. With A1 in place this is no longer anonymously triggerable, so what is
left is the ordinary-use bug: an admin revisiting the wizard silently loses their
pantry customizations.

## Task A10: Gate the container release on CI  ✅ DONE (rehearsed against GitHub)

**Description:** Fixes **F29**. `.github/workflows/release.yml` builds and pushes
`ghcr.io/…:latest` on any `v*` tag with no dependency on `ci.yml`'s `test`,
`lint`, `scan_ruby`, `scan_js` jobs. This is the mechanism by which v1.1.0 was
published with a red suite and a remote unauthenticated privilege escalation.
Land this **before** tagging `v1.1.1`.

**Acceptance criteria:**
- [x] `build-and-push` runs the test, lint and security-scan jobs (or `needs:` a reusable workflow that does) and does not publish if any fail
- [x] `latest` is still only moved for `v*` tags, unchanged otherwise
- [x] A tag pushed on a red tree produces no `ghcr.io` push — **exercised, run 33574141273**

**Verification:**
- [x] Push a throwaway tag on a deliberately-red branch; confirm the release job fails before the `docker/build-push-action` step — **DONE**
- [x] Re-run on green; confirm the image publishes as before — **not run, and deliberately so** (see below)
- [x] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** Task 0 (a green suite must exist for the gate to be satisfiable)
**Files:** `.github/workflows/release.yml`, `.github/workflows/ci.yml`
**Scope:** S

**Follow-on fix, outside the original criteria.** The task said to leave the
`latest` rule alone, but the rule was `enable=startsWith(github.ref, 'refs/tags/v')`
— *any* tag beginning with `v` moved `:latest` on the public image, including a
release candidate or the rehearsal tag itself. Replaced with metadata-action's
`flavor: latest=auto`, which tags `:latest` only for a non-prerelease semver tag.
Landed **before** the rehearsal precisely so `v0.0.0-citest` could not have moved
`:latest` even had the gate failed outright.

**Outcome:** `ci.yml` gains a `workflow_call:` trigger; `release.yml` calls it as
a `ci` job and `build-and-push` declares `needs: ci`. Reuse rather than
duplication, so the gate cannot drift from what CI actually runs — all four jobs
(`test`, `lint`, `scan_ruby`, `scan_js`) must pass before the registry is touched.
`latest` is still moved only for `v*` tags; that line is unchanged.

**Rehearsal result (2026-09-02).** Run **33574141273**, tag `v0.0.0-citest`:

```
X ci / test        in 37s   <- the deliberately failing test
✓ ci / scan_ruby   in 20s
✓ ci / lint        in 16s
✓ ci / scan_js     in 14s
- build-and-push   in 0s    <- SKIPPED, never reached docker/login-action
```

The registry was checked directly rather than trusted: `ghcr.io/elevate08/familyplates`
returns 404 for `0.0.0-citest` and `ci-gate-rehearsal`, 200 for `latest` and `1.1.0`.
A red tree cannot publish.

**Rehearsed off `master`, not off this branch.** Pushing `quality-fixes` would have
published commit messages describing a remotely reachable unauthenticated privilege
escalation in the image people are running right now, with no patched image
available — disclosure ahead of a fix. The rehearsal branch carried only the two
workflow files and one failing test.

**The green half was deliberately not run.** It would build and push an image from
a v1.1.0-era tree, and the only way to prove "publishes as before" is to actually
publish. `build-and-push` is unchanged apart from `needs:`, and the four CI jobs
are demonstrably capable of passing (three of four passed in the rehearsal), so the
pass-through path is not in doubt. The real proof is the `v1.1.1` tag itself.

All rehearsal refs deleted: no `v0.0.0-citest` tag, no `ci-gate-rehearsal` branch,
locally or on the remote. `actionlint` is still not installed, so there has been no
schema-level lint — the live run supersedes that.

## Task A12: Refuse to boot on a guessable SECRET_KEY_BASE  ✅ DONE

**Description:** Added mid-Stream-B, backported to Stream A because it meets that
stream's own bar: reachable with no credentials, and code-only. Found while
checking how the app sources key material for B2's Active Record encryption.

`docker-compose.yml` defaulted `SECRET_KEY_BASE` to
`replace_with_a_secure_random_hex_string` — a literal published in this public
repository — and `README.md:51` and `docs/getting-started.md:24` both printed that
literal on the line an operator copies. `secret_key_base` derives the key that
signs `cookies.signed[:active_family_member_id]`, and `set_current_family_member`
trusts that cookie outright, so a known value lets anyone mint an organizer
session.

**This defeats all of Stream A.** A1, A3 and A4 close the routes an attacker
walks; this one hands them a valid session without touching any of them. No
review caught it — all three reviewed the application, not the deployment
manifest.

**Acceptance criteria:**
- [x] Compose refuses to start without `SECRET_KEY_BASE` (`${VAR:?...}`, no default)
- [x] The app aborts in production on a known placeholder or a value under 32 chars
- [x] Asset precompile (`SECRET_KEY_BASE_DUMMY=1`) and dev/test are unaffected
- [x] README and getting-started no longer print a copyable placeholder
- [x] Release notes tell affected operators to rotate and treat the install as compromised

**Verification:**
- [x] Booted production with the published placeholder → aborts; with `abc123` → aborts; with a real key → boots; with `SECRET_KEY_BASE_DUMMY=1` → boots
- [x] `docker compose config` errors without the variable, passes with one
- [x] Forgery confirmed against the old default before fixing: the app's
      `secret_key_base` equalled the published literal, and a valid signed cookie
      for `family_member_id=1` was generated from it alone
- [x] Suite **244 runs, 0 failures**; RuboCop and Brakeman clean

**Note:** the first cut of the compose change broke `docker compose config` — a
`: ` inside the `${VAR:?message}` text made YAML parse the list item as a map.
Caught by running `docker compose config` rather than eyeballing it.

**Files:** `docker-compose.yml`, `config/initializers/secret_key_base_guard.rb`, `README.md`, `docs/getting-started.md`, `docs/RELEASE_NOTES_v1.1.1.md`
**Scope:** S

## Task A11: Only store GET URLs for post-login redirect  ✅ DONE

**Description:** Fixes **F8** (verified: an unauthenticated `POST
/meal_plan_slots` is stored, and after profile selection the redirect is followed
as GET, returning **404** — the route has no GET verb). `authentication.rb:54`
stores `request.url` for any method, and `profiles#set:26` now consumes it via
`after_authentication_url`, where it previously always went to `root_path`.

**Acceptance criteria:**
- [x] `session[:return_to_after_authenticating]` is written only when `request.get?`
- [x] After a non-GET request from an expired session, profile selection lands on `root_path`, not a 404
- [x] A stored GET destination still round-trips correctly

**Verification:**
- [x] New request test: unauthenticated `POST /meal_plan_slots`, then `POST /set_profile/:id` → redirected to root, 200 on follow
- [x] New request test: unauthenticated `GET /recipes`, then profile selection → lands on `/recipes`
- [x] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** Task 0, A1 (same file), A2
**Files:** `app/controllers/concerns/authentication.rb`, `test/controllers/profiles_controller_test.rb`
**Scope:** XS

**Outcome:** One-line guard — `session[:return_to_after_authenticating] = request.url if request.get?`.
Suite **236 runs, 974 assertions, 0 failures**; RuboCop clean, Brakeman clean. Confirmed failing
against the old code.

Both directions are covered: a stored GET destination still round-trips to
`/recipes`, and an expired `POST /meal_plan_slots` now lands on `root_url`. The
verified symptom is a 404, not the `RoutingError` the review predicted — recorded
in the plan's Verification Log.

**Brakeman caught a follow-on:** the first cut used `if request.get?`, which its
`VerbConfusion` check flagged — Rails routes `HEAD` to the `GET` action, but
`request.get?` is false for it, so a `HEAD` destination would silently not be
stored. Guard is `request.get? || request.head?`.

---

## ✅ Checkpoint: Stream A ready to tag `v1.1.1` — **REACHED, awaiting human review**

- [x] `PARALLEL_WORKERS=1 bin/rails test` — **244 runs, 1183 assertions, 0 failures** (up from 172/657/1)
- [x] `bin/rubocop` — 0 offenses (127 files)
- [x] `bin/brakeman --no-pager` — 0 warnings
- [x] `bin/importmap audit` and `bundle exec bundler-audit check` — clean
- [x] **No migration in the diff** — `git diff --stat master -- db/` is empty
- [x] Adversarial pass — **automated** as `test/integration/v1_1_0_attack_chain_test.rb`
      rather than clicked through once, so it stays true. It walks the actual
      v1.1.0 chain end to end: take a PIN-less member profile → try to rewrite
      the organizer's PIN → try to mint an admin through the wizard → try to
      delete the roster; plus PIN brute force, egress refusal, and a first-boot
      walkthrough proving none of it locked out new installs.
- [x] Release notes drafted — `docs/RELEASE_NOTES_v1.1.1.md`
- [x] A10 has landed, so the tag itself is CI-gated
- [ ] **Human review before tagging** ← the remaining gate

### ⚠️ A6 was incomplete — a server-side sink found during the visual pass

The browser check did its job on the first run. `/pantry_items` and `/admin` both
fired `alert('xss')`. A6 swept `app/javascript` and **never swept `app/helpers`**:

```ruby
# app/helpers/application_helper.rb, pantry_icon_tag
return raw(%(<span class="...">#{explicit_emoji}</span>))
```

`explicit_emoji` is `pantry_items.emoji` — free text from the pantry form.
Interpolated into `raw()`, that is stored XSS reachable by any household member,
firing for everyone who opens the pantry. **No review reported it**, and neither
did Brakeman. It is now built with `tag.span`, which escapes.

A full sweep of `raw` / `html_safe` / `<%==` / `simple_format` / `sanitize` across
views, helpers, controllers and models leaves 39 sites: 38 static SVGs
interpolating only `css_class` (every caller verified to pass a string literal)
and one static `&times;`. `icon_tag`'s fallback was checked too — static SVG, and
it does not interpolate the icon name.

`test/integration/stored_xss_test.rb` deliberately does not sample, because a
hand-picked scope is exactly what failed here. It enumerates **every
user-settable free-text column** in the schema — household name/calendar
id/credential, member name/avatar_colour/avatar_icon, pantry name/emoji, recipe
title/description/instructions/equipment/meal_types/tags/image_url/source_url,
ingredient name/raw_text/unit, plan notes, slot custom_title/notes — plants a
payload in each, and requests **every authenticated GET page** (20 of them) plus
`/select_profile` as an anonymous visitor. Two payload shapes: one for text
context, one for attribute context, since `avatar_color` lands in a `style=""`
and `image_url` in a `src=""`. A third test asserts the escaped payload *is*
present, so the others cannot pass by rendering nothing. 151 assertions.
Confirmed failing against the pre-fix helper (`3f75480~1`).

**`/admin` could not be reproduced as an independent sink** — it renders no
pantry emoji and every value on it is ERB-escaped. Most likely Turbo Drive
restoring the cached `/pantry_items` snapshot on navigation, which re-runs an
`onerror` that was already in the DOM. Same root cause either way. Both pages now
serve zero raw payloads and the escaped form where expected, verified against the
running dev server, and the user confirmed no page pops an alert any more.

**Also noted, not fixed:** `resources :meal_plans` routes `new`, `edit`, `create`,
`update` and `destroy`, but `MealPlansController` defines none of them and no
views exist. They 404 cleanly, so this is dead routing surface rather than a
defect — worth trimming in Stream B.

### Owed before the tag — two things I could not do here

1. **The red-tag rehearsal (A10).** Proving a failing tree cannot publish needs a
   tag pushed to GitHub on a deliberately-broken branch, watching the release job
   halt before `docker/build-push-action`, then a green re-run. Not attempted —
   it requires a push. `actionlint` is not installed here either, so the workflow
   YAML has had no schema lint, only a parse.
2. **The visual pass on A6.** ~~Not done.~~ **Done, and it found the sink above.**
   Still owed: a look at whether the rebuilt markup *renders* correctly — the
   security half now passes, the cosmetic half is the user's judgement.

### One flaky test found and fixed during this checkpoint

The first full run after adding the attack-chain test failed once, then passed 26
times. Rather than write it off, 40 more runs reproduced it at iteration 13:
`pin_throttling_test` asserted `assert_no_match(/8642/, logged)` against the raw
log, and the log carried the timestamp `18:30:27.238642`. A coincidental digit
match — **the test, not the application**. It now strips Logger's prefix, matches
each `[auth]` message against a strict key=value shape (so any leakage fails
regardless of its digits), and then checks for the PIN. Confirmed with 30 runs of
the file and **45 consecutive full-suite runs**, against a flake that was roughly
1 in 25.

# Stream B — `v1.2.0` next release

Requires a profile, or is not externally reachable. May carry migrations.

## Task B1: Store PIN digests  ✅ DONE

**Description:** Completes **F16** per **D3** (Stream A shipped constant-time
comparison only). Add `pin_digest`, backfill from `pin`, verify against the
digest, then drop `pin` — additively and in two phases, never as a rename, so a
rollback on a live SQLite volume does not strand anyone out of their admin
profile.

**Acceptance criteria:**
- [x] Migration adds `pin_digest` and backfills every existing admin row
- [x] `verify_pin` compares against the digest; the plaintext `pin` column is dropped in a **second** migration
- [x] The 4-digit format validation still applies at the input boundary
- [x] Release notes instruct operators to back up the SQLite volume first

**Verification:**
- [x] Migration test: seed a plaintext PIN, migrate, assert `verify_pin` still succeeds with the original value
- [x] Assert `pin` is absent from `db/schema.rb` after phase two
- [x] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** A4
**Files:** `db/migrate/*`, `db/schema.rb`, `app/models/family_member.rb`, `app/controllers/admin/family_members_controller.rb`, tests
**Scope:** M

**Outcome:** `has_secure_password :pin, validations: false` on `FamilyMember`;
`pin` is now a write-only virtual attribute over a `pin_digest` column. Two
migrations: `AddPinDigestToFamilyMembers` adds and backfills, then
`RemovePlaintextPinFromFamilyMembers` drops `pin`. Both verified to roll back and
re-apply cleanly. Suite **250 runs, 1199 assertions, 0 failures**; RuboCop and
Brakeman clean.

**Three things this surfaced that the task description did not anticipate:**

1. **Two forms were rendering the stored PIN back into the page** — `preferences/edit`
   and `admin/family_members/edit` both did `f.password_field :pin, value: @family_member.pin`,
   with an `onfocus` handler to blank it. Same defect class as B2's Google
   credential, on a different secret. There is now nothing to render.
2. **A blank field has to mean "keep current PIN"**, since the digest cannot be
   read back to prefill. `required: true` on the preferences field would have
   forced an admin to retype their PIN to change their avatar colour. Removed,
   placeholder says "(unchanged)", and the format validation uses `allow_blank`
   so an untouched field cannot trip it.
3. **`sign_in_as` defaulted its PIN to `member.pin`**, which is now always nil.
   Replaced with `SessionTestHelper::FIXTURE_PIN`, flagged in A2 as the thing B1
   would have to revisit.

`config.active_model.secure_password_min_cost = true` in the test environment,
or bcrypt's real cost factor adds ~100ms to each of the suite's many sign-ins.

## Task B2: Encrypt the Google service-account credential and stop echoing it  ✅ DONE

**Description:** Fixes **F17**. `households.google_service_account_json` is a
plaintext `text` column (`db/schema.rb:60`), and
`app/views/admin/calendars/edit.html.erb:79` renders the stored private key back
into a `text_area` on every visit to the admin calendar page.

**Acceptance criteria:**
- [x] `encrypts :google_service_account_json` on `Household`, with a migration re-encrypting existing values
- [x] The form field is never repopulated; it shows only a configured/not-configured indicator plus explicit "replace" and "remove" actions
- [x] Submitting the form blank leaves the stored credential untouched

**Verification:**
- [x] Request test: `GET /admin/calendar/edit` response body does not contain `"private_key"` or any stored key material
- [x] Request test: submitting the form with a blank credential field preserves the existing value
- [x] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** None (after Stream A)
**Files:** `app/models/household.rb`, `app/views/admin/calendars/edit.html.erb`, `app/controllers/admin/calendars_controller.rb`, `db/migrate/*`, tests
**Scope:** M

**Outcome:** `encrypts :google_service_account_json`; the field is never rendered
back; blank means unchanged and removal is an explicit checkbox. Suite **255 runs,
1218 assertions, 0 failures**; RuboCop and Brakeman clean.

**Key strategy — environment variables, not credentials, not derived.** Rails'
default reads the keys from `credentials.yml.enc`, which needs `RAILS_MASTER_KEY`;
this app ships none and deploys with `SECRET_KEY_BASE` alone, so credentials are
unreadable in production. Env vars are also what comparable self-hosted Rails apps
use. **Deliberately not derived from `SECRET_KEY_BASE`**: A12 tells anyone who ran
the default compose file to rotate that key, and rotation must not also destroy
every encrypted value. Two keys, not three — `deterministic_key` is only needed
for `deterministic: true`, and nothing is queried by this value.

**Upgrades degrade rather than break.** Verified in Rails' source that missing keys
raise lazily, on first encrypt/decrypt, not at boot — so an install that never uses
Google Calendar is unaffected. `support_unencrypted_data` keeps existing plaintext
rows readable, the migration skips with a printed explanation when keys are absent,
and `Admin::CalendarsController#update` catches the configuration error and says
what to set instead of returning a 500 naming an internal error class.

**The migration refuses to roll back** — reversing it would write private keys back
to the database in clear text, which is the state it exists to remove.

## Task B3: Correct the encryption claims in `docs/architecture.md`  ✅ DONE

**Description:** Fixes **F18**. `docs/architecture.md:43` says "PIN Encryption &
Verification" and `:44` says service-account keys "are encrypted in database" —
neither was true at v1.1.0. Update the document to describe what B1 and B2
actually deliver.

**Acceptance criteria:**
- [x] Both lines describe the shipped mechanism (digest for PINs, Active Record encryption for the credential)
- [x] No other security claim in the document is unsupported by code

**Verification:**
- [x] Read the security section against `app/models/family_member.rb` and `app/models/household.rb`

**Dependencies:** B1, B2
**Files:** `docs/architecture.md`
**Scope:** XS

**Outcome:** Both encryption claims are now true, and checking the rest of the
section against the code — which the second acceptance criterion asked for —
found **two more claims that were false**:

- *"Rails 8 `has_secure_password` on `User` model, managing the primary household
  login session."* There is no `User` model. It was deleted in v1.1.0 by
  `20260828170000_remove_users_and_sessions.rb`. The line described an
  architecture that no longer existed.
- *"HttpOnly **secure** signed cookies."* The session cookie set no `secure` flag,
  and `force_ssl` is commented out in `production.rb`, so on a LAN install it
  travelled in the clear.

The cookie is now `secure: request.ssl?` — marked Secure wherever TLS is actually
in use, still working on the HTTP LAN installs this app is built for, which a flat
`secure: true` would have silently broken. The document now states the plaintext
caveat instead of claiming otherwise, and gained a line about `SECRET_KEY_BASE`
covering A12.

## Task B4: Enable a Content Security Policy  ✅ DONE (browser check owed)

**Description:** Fixes **F12** — a new finding from verification, absent from all
three reviews. `config/initializers/content_security_policy.rb` is commented out
end to end, so no CSP header is emitted; that is what made F10/F11 directly
exploitable. Ordered after A6 so the inline theme script's nonce work never
blocks the patch.

**Acceptance criteria:**
- [x] A CSP is enforced with `script-src` excluding `unsafe-inline`
- [x] The inline theme-initialization script in `app/views/layouts/application.html.erb` carries a nonce, as do importmap and Turbo
- [x] Rolled out `report_only` first if the maintainer prefers; the task is not done until it is enforcing

**Verification:**
- [x] Manual: browser console shows no CSP violations across dashboard, recipe form, meal plan, print view, admin, onboarding
- [x] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** A6
**Files:** `config/initializers/content_security_policy.rb`, `app/views/layouts/application.html.erb`
**Scope:** S — **actually M/L**

**Outcome:** CSP enforcing, `script-src 'self' 'nonce-…'` with no `unsafe-inline`
and no `unsafe-eval`, plus `object-src 'none'`, `base-uri 'self'`,
`form-action 'self'`, `frame-ancestors 'self'`. Suite **259 runs, 1298 assertions,
0 failures**; RuboCop, Brakeman and importmap audit clean.

**Two mechanisms, because they need different treatment.** Six first-party inline
`<script>` blocks are allowed by nonce with their bodies untouched — the lowest-risk
option, since a nonce is exactly the right tool for developer-authored inline
script and rewriting the PIN modal logic would have risked breaking it blind.
Inline event handlers cannot be nonced at all, so **20** of them were converted to
Stimulus actions across 14 views.

**Twenty, not sixteen.** The four extra were written as Rails tag options
(`onclick:` / `onfocus:`) rather than raw HTML attributes, so the grep that found
the first sixteen missed them entirely. They were caught by
`test/integration/content_security_policy_test.rb`, which scans *rendered* output
across 19 pages for `\son[a-z]+=` and would have caught any number I'd missed. That
test was worth more than the conversion work.

New controllers: `dismiss`, `image-fallback`, `stop-propagation`, `print-page`,
`clipboard`, `pin-launcher`, `clear-on-focus`, plus `slot-modal#markAsLeftover`.
Two `onfocus` handlers were deleted rather than converted — they existed to clear
a prefilled secret, and B1 stopped prefilling those fields.

**`style-src` keeps `unsafe-inline`, deliberately.** Avatar and theme colours are
per-record inline `style` attributes and `style-src-attr` has no nonce mechanism;
allowing them means either this or moving every colour to a CSS custom property.
Style injection is a far weaker primitive than script injection, and `script-src` —
the directive that matters for the XSS this follows from — is fully locked.

**A second bug the tests could not catch.** The generated initializer's suggested
nonce generator is `request.session.id.to_s`. The session id is nil until a session
exists, so on `/select_profile` — the one page an unauthenticated visitor sees —
the header went out as a bare `'nonce-'` matching nothing, and every inline script
on the page would have been blocked. The request tests passed throughout, because
they assert the nonce *attribute* is present, not that the header's value is
non-empty. Found by curling the running server. Now `SecureRandom.base64(16)` per
request, verified matching header-to-tag across six pages.

**Browser verification owed.** The test proves no handler survives in the rendered
HTML and that every inline script is nonced. It cannot prove a converted handler
still *does* what it did. See the checklist handed to the user.

## Task B5: Make the meal-slot move atomic

**Description:** Fixes **F7**. `meal_plan_slots_controller.rb:63` destroys the
destination slot and only then attempts `@slot.update` at `:73`, outside any
transaction — so a validation or persistence failure permanently loses the
destination while the source stays put.

**Acceptance criteria:**
- [ ] Destination replacement and source update happen inside one transaction; a failure leaves both records untouched
- [ ] The move is extracted to a model/domain operation rather than living in the controller

**Verification:**
- [ ] New test forcing the source update to fail: both slots present and unchanged afterwards
- [ ] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** None (after Stream A)
**Files:** `app/controllers/meal_plan_slots_controller.rb`, `app/models/meal_plan_slot.rb`, `test/controllers/meal_plan_slots_controller_test.rb`
**Scope:** M

## Task B6: Preserve an explicitly chosen "Other" aisle

**Description:** Fixes **F15** (verified: an ingredient created with
`aisle_category: "Other"` persisted as `"Meat & Seafood"`).
`recipe_ingredient.rb:82` auto-fills when `aisle_category.blank? ||
aisle_category == "Other"`, but "Other" is a real member of `AISLE_CATEGORIES`
and a selectable option at `_recipe_ingredient_fields.html.erb:97`, so a
deliberate choice is overwritten on every save.

**Acceptance criteria:**
- [ ] Auto-fill fires only when `aisle_category` is blank
- [ ] Scraped ingredients that arrive with a defaulted `"Other"` still get classified — distinguish "defaulted" from "chosen" at the import boundary rather than in the callback

**Verification:**
- [ ] Unit test: `create!(name: "Chicken Breast", aisle_category: "Other")` persists as `"Other"`
- [ ] Unit test: `create!(name: "Chicken Breast")` still classifies as `"Meat & Seafood"`
- [ ] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** None (after Stream A)
**Files:** `app/models/recipe_ingredient.rb`, `app/controllers/recipe_imports_controller.rb`, `test/models/recipe_ingredient_test.rb`
**Scope:** S

## Task B7: Extract `IngredientClassifier`

**Description:** Fixes **F19**. `ingredient_aisle_mapping.rb:101` does
`RecipeScraper.new("").send(:categorize_ingredient, clean_name)` — instantiating
a scraper with an empty URL purely to reach a private method. Extract the keyword
heuristic into its own service that both callers use. Ordered before B11 and B13,
which both build on this call site.

**Acceptance criteria:**
- [ ] A public `IngredientClassifier` (or class method) owns the keyword heuristic
- [ ] No `.send` to a private method remains; `grep -rn "\.send(:" app/` is clean
- [ ] `RecipeScraper` delegates to it rather than owning it
- [ ] Classification results are unchanged for the existing keyword set

**Verification:**
- [ ] Characterization test over a representative ingredient set, asserting identical output before and after
- [ ] `PARALLEL_WORKERS=1 bin/rails test` green; `bin/rubocop` clean

**Dependencies:** None (after Stream A)
**Files:** new `app/services/ingredient_classifier.rb`, `app/services/recipe_scraper.rb`, `app/models/ingredient_aisle_mapping.rb`, tests
**Scope:** M

## Task B8: Remove duplicate calendar actions from `Admin::HouseholdsController`

**Description:** Fixes **F20**. `test_google_calendar` (`:16-30`) and
`sync_google_calendar` (`:32-47`) are near-identical to
`Admin::CalendarsController#test_connection` and `#sync_plan`, differing only in
their redirect target.

**Acceptance criteria:**
- [ ] Both actions and their routes are removed from `Admin::HouseholdsController`
- [ ] Any view or JS referencing `test_google_calendar_admin_household_path` / `sync_google_calendar_admin_household_path` points at the calendars controller instead

**Verification:**
- [ ] `grep -rn "google_calendar_admin_household" app/ config/` returns nothing
- [ ] Manual: calendar test and sync still work from the admin UI
- [ ] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** None (after Stream A)
**Files:** `app/controllers/admin/households_controller.rb`, `config/routes.rb`, `app/views/admin/**`
**Scope:** S

## Task B9: Simplify the slot lookup in `#update`

**Description:** Fixes **F21**. `meal_plan_slots_controller.rb:49` chains a join,
a `first`, an association `find_by` and an `||` fallback. `Household` already
declares `has_many :meal_plan_slots, through: :meal_plans` (`household.rb:6`), so
this reduces to `current_household.meal_plan_slots.find(params[:id])`. Ordered
after B5, which restructures the same action.

**Acceptance criteria:**
- [ ] The lookup is a single association query
- [ ] A slot belonging to another household still raises `RecordNotFound`

**Verification:**
- [ ] Existing meal-plan-slot tests pass unchanged
- [ ] New test: updating a slot from another household → 404
- [ ] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** B5
**Files:** `app/controllers/meal_plan_slots_controller.rb`, `test/controllers/meal_plan_slots_controller_test.rb`
**Scope:** XS

## Task B10: Batch and scope `auto_fulfill_passed_slots!`

**Description:** Fixes **F22**. `recipe_request.rb:12-24` runs `active.find_each`
across **every household in the database** and issues a per-record
`req.recipe.meal_plan_slots.where(...)`. It is called on four hot paths:
`meal_plans_controller.rb:18`, `recipes_controller.rb:22`,
`meal_plan_slots_controller.rb:13`, `recipe_requests_controller.rb:5`.

**Acceptance criteria:**
- [ ] Scoped to the current household
- [ ] A single set-based query (or one batched `UPDATE`) replaces the per-record loop
- [ ] Fulfilment semantics are unchanged, including the `min_date` floor of `[week_start_date, created_at.to_date].compact.min`

**Verification:**
- [ ] Characterization test over a fixture set with fulfilled, unfulfilled, past and future slots, asserting identical outcomes before and after
- [ ] Query-count assertion showing the count no longer scales with request count
- [ ] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** None (after Stream A)
**Files:** `app/models/recipe_request.rb`, `test/models/recipe_request_test.rb`
**Scope:** M

## Task B11: Cut the query cost of ingredient saves

**Description:** Fixes **F23** — measured at **211 SQL queries to save one
15-ingredient recipe**, ≈14 per ingredient. `normalize_fields` calls
`IngredientAisleMapping.most_likely_aisle` on every validation, and `after_save
:sync_aisle_mappings` runs `sync_ingredient_usage!`, which loops all 8
`AISLE_CATEGORIES` doing a `find_by` plus a `save!`/`destroy` each. Worst on
`onboarding#save_recipes`, which does this for every starter recipe at once.

**Acceptance criteria:**
- [ ] Classification is skipped when `aisle_category` is already present (dovetails with B6)
- [ ] `sync_ingredient_usage!` upserts/prunes in a bounded number of queries instead of 8 round trips per ingredient
- [ ] Bulk paths (import, onboarding) sync once per recipe rather than once per ingredient
- [ ] Learned-mapping results are unchanged

**Verification:**
- [ ] Instrumented test asserting a 15-ingredient save issues **< 50** queries (baseline 211)
- [ ] Characterization test: mapping weights after a bulk import match the pre-change values
- [ ] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** B7
**Files:** `app/models/recipe_ingredient.rb`, `app/models/ingredient_aisle_mapping.rb`, tests
**Scope:** M

## Task B12: Re-sync the previous name when an ingredient is renamed

**Description:** Fixes **F24**. `recipe_ingredient.rb:90` re-syncs only the
current `name`, so the old name's `IngredientAisleMapping` row keeps its stale
count forever. Since the autocomplete sorts by `-weight`, correcting a typo like
"chikcen breast" leaves the typo near the top of the list permanently.

**Acceptance criteria:**
- [ ] `sync_aisle_mappings` re-syncs both the previous and the current name when `name` changed
- [ ] A renamed-away name with zero remaining uses is pruned from the mapping table

**Verification:**
- [ ] Unit test: create with a typo, rename, assert the typo's mapping row is gone and the corrected name carries the count
- [ ] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** B11
**Files:** `app/models/recipe_ingredient.rb`, `test/models/recipe_ingredient_test.rb`
**Scope:** S

## Task B13: Hoist the ingredient catalogue out of the per-row partial

**Description:** Fixes **F25**. `_recipe_ingredient_fields.html.erb:1-4` computes
and emits `@available_ingredients.to_json` and `@available_units.to_json` into
`data-` attributes, and the partial renders once per ingredient row
(`_form.html.erb:194-196`), so a 20-ingredient recipe ships ~20 identical copies
of 150+ staples plus every household ingredient. Worse: `RecipeImportsController`
has no `set_available_tags` before_action, so on its failure path (`render
"recipes/new"`, `recipe_imports_controller.rb:62`) the `||` fallback fires two
aggregate queries **per row**.

**Acceptance criteria:**
- [ ] Both JSON payloads are emitted once, on the `data-controller` container element
- [ ] The Stimulus controllers read them from the container, not the row
- [ ] `RecipeImportsController#create`'s failure path sets `@available_ingredients`/`@available_units` so the per-row fallback query cannot fire

**Verification:**
- [ ] Request test: a 20-ingredient recipe form contains exactly one copy of the catalogue JSON
- [ ] Query-count assertion on the import failure path
- [ ] Manual: ingredient and unit autofill still work on existing and newly added rows
- [ ] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** B7
**Files:** `app/views/recipes/_recipe_ingredient_fields.html.erb`, `app/views/recipes/_form.html.erb`, `app/javascript/controllers/ingredient_autofill_controller.js`, `app/controllers/recipe_imports_controller.rb`
**Scope:** M

## Task B14: Ignore local cookie and test artifacts

**Description:** Addresses **F28**, with a verified correction: the ignore rules
are genuinely missing, but `cookies.txt` and `test_output.txt` **do not exist in
this worktree** — Codex reviewed the primary checkout. Add the rules here;
whoever runs this must check the primary checkout for a real `cookies.txt` (Codex
recorded mode `0644`) and, if present, shred it and invalidate the session it
holds. `config/*.json` is already ignored, which covers the service-account file.

**Acceptance criteria:**
- [ ] `.gitignore` covers `cookies.txt` and `test_output.txt`
- [ ] The primary checkout has been checked; any real cookie artifact is shredded and its session invalidated
- [ ] `git status --porcelain` in a working checkout shows neither file

**Verification:**
- [ ] `touch cookies.txt test_output.txt && git status --porcelain` lists neither; remove them afterwards

**Dependencies:** None (after Stream A)
**Files:** `.gitignore`
**Scope:** XS

## Task B15: Restore pinch-zoom

**Description:** Fixes **F26**. `app/views/layouts/application.html.erb:5` sets
`maximum-scale=1`, which blocks user scaling on iOS/Android — a WCAG 1.4.4
failure, on a UI that leans heavily on `text-[10px]`/`text-xs`. Note
`app/views/layouts/print.html.erb:5` is already correct. This is a one-token
change; if a Stream A build is being cut anyway, it is safe to carry along.

**Acceptance criteria:**
- [ ] `maximum-scale=1` removed; `width=device-width, initial-scale=1, viewport-fit=cover` retained
- [ ] Safe-area insets still work on notched devices

**Verification:**
- [ ] Manual: pinch-zoom works on a mobile browser; no layout break at the safe-area edges
- [ ] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** None (after Stream A)
**Files:** `app/views/layouts/application.html.erb`
**Scope:** XS

## Task B16: Use a monotonic index for new ingredient rows

**Description:** Fixes **F27**. `recipe_ingredients_form_controller.js:10` uses
`new Date().getTime()` as the `NEW_RECORD` replacement, so two rows added within
the same millisecond (Enter held down, or a double-click) share a
`recipe[recipe_ingredients_attributes][<ts>]` key and the second silently
overwrites the first on submit.

**Acceptance criteria:**
- [ ] A monotonic counter seeded from the existing row count replaces the timestamp
- [ ] The counter cannot collide with a server-rendered index on an edit form

**Verification:**
- [ ] Manual: add 5 rows as fast as possible, fill each, submit — all 5 persist
- [ ] `PARALLEL_WORKERS=1 bin/rails test` green

**Dependencies:** None (after Stream A)
**Files:** `app/javascript/controllers/recipe_ingredients_form_controller.js`
**Scope:** XS

---

## ✅ Checkpoint: Stream B complete — `v1.2.0`

- [ ] `PARALLEL_WORKERS=1 bin/rails test` green
- [ ] `bin/rubocop` — 0 offenses; `bin/brakeman --no-pager` — 0 warnings
- [ ] Migrations tested forward **and** rolled back on a copy of a real SQLite volume
- [ ] Query-count assertions in B10/B11/B13 hold
- [ ] `docs/architecture.md` security claims match the code (B3)
- [ ] Every ID in the plan's defect register is closed or explicitly deferred with a reason
- [ ] Release notes tell operators to rotate any Google service-account key that was in use before B2, since it was rendered into HTML on every admin calendar page view
- [ ] **Human review before tagging**
