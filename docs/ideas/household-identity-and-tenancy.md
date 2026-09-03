# Household Identity, Sessions & Multi-Tenancy

> Status: ideation complete, not yet planned for implementation.
> "What Exists Today" re-verified against `master` @ 56b9d23 on 2026-09-03.
> Reference-app snippets re-verified against upstream `main` on the same date.
> Supersedes the "Not Doing" entries on OAuth and per-member logins in
> [`single-family-admin-and-preferences.md`](./single-family-admin-and-preferences.md).

## Problem Statement

**How might we put a real front door on a self-hosted family kitchen appliance — one that proves _which household_ you are and survives being exposed to the internet — without adding a single tap for the kid at the fridge tablet?**

## Context: What Exists Today

FamilyPlates has no authentication. It has a profile picker.

* There is **no `User` model and no `users` table**. `docs/architecture.md:41` now states this outright; the only residue is the ER diagram at `docs/architecture.md:23`, which still draws a `Household ||--o{ User` edge with no model behind it. `bcrypt` is in the `Gemfile` and *is* used — for `FamilyMember`'s PIN digest, not for any account model.
* `Authentication#set_current_family_member` (`app/controllers/concerns/authentication.rb:32`) reads the signed, `HttpOnly`, `SameSite=Lax` `active_family_member_id` cookie. Possession of that cookie *is* the session — there is no `sessions` row to revoke.
* Any visitor reaching the app gets `/select_profile` and can one-tap into any non-admin profile. Only `role: "admin"` profiles require a PIN (`app/models/family_member.rb:45`), and an admin profile can no longer be saved without one (`admin_requires_a_pin`). Entry is throttled to 10 attempts / 3 minutes, per IP *and* per profile, on one budget shared across both PIN paths (`app/controllers/concerns/pin_throttling.rb`).

Three properties of the current code are load-bearing for single-tenancy and become defects the moment a second household exists:

1. **`/set_profile/:id` is an unauthenticated global finder.** `ProfilesController#set` (`app/controllers/profiles_controller.rb:16`) calls `FamilyMember.find(params[:id])` under `allow_unauthenticated_access`, and non-admin members have no PIN. With one household this is harmless — it grants exactly what the open picker already grants by design. With two, it is cross-tenant account takeover by ID enumeration. `app/channels/application_cable/connection.rb:13` shares the pattern.
2. **The second household can never onboard.** `Household.none?` / `Household.exists?` is the "is this deployment configured?" test in six places (`authentication.rb:49,66`, `home_controller.rb:5`, `sessions_controller.rb:5`, `profiles_controller.rb:8`, `shared/_navbar.html.erb:59`), and `OnboardingController#ensure_household_unconfigured` explicitly blocks setup once one exists. In multi-tenant that predicate is permanently false.
3. **`Household.first` is the ambient fallback tenant** (`authentication.rb:25,36,39`). An unauthenticated request currently resolves `Current.household` to whichever household sorts first. 87 `current_household` call sites depend on that fallback.

**Already fixed, since this doc was first drafted:** PINs are no longer plaintext. `family_members.pin_digest` holds a bcrypt digest written through `has_secure_password :pin` (`app/models/family_member.rb:26`); `pin` is a write-only virtual attribute that cannot be read back off a record, and verification goes through bcrypt's constant-time compare (`FamilyMember#verify_pin`). The Phase 0 PIN-migration task this doc originally carried is done and has been struck below.

## Prior Art: The Rails Reference Apps

Rails maintains a curated library of exemplary open-source apps at [rubyonrails.org/docs/reference-apps](https://rubyonrails.org/docs/reference-apps). All three listed are 37signals apps, and all three are directly relevant here:

| App | Deployment shape | What it settles for us |
| :--- | :--- | :--- |
| [fizzy](https://github.com/basecamp/fizzy) | Self-hosted **and** SaaS from one repo (`saas/`, `Gemfile.saas`) | The dual-mode reference: tenancy, identity, magic codes, enumeration |
| [once-campfire](https://github.com/basecamp/once-campfire) | Self-hosted appliance, single tenant | First-run setup, sliding sessions, join codes, profile transfer |
| [writebook](https://github.com/basecamp/writebook) | Self-hosted appliance, single tenant | First-run setup, minimal session lookup |

The split matters: **the two appliances use `has_secure_password`; the dual-mode app uses magic codes and passkeys.** 37signals chose passwords precisely where SMTP cannot be assumed. See "Credential choice" below — this reopens a decision this doc had closed.

### fizzy — the dual-mode reference

[basecamp/fizzy](https://github.com/basecamp/fizzy) has exactly this identity shape. Its decisions are cited below where they settle a question.

**Terminology map:** fizzy `Identity` = this doc's `User` (email credential) · fizzy `User` = `FamilyMember` (per-tenant profile) · fizzy `Account` = `Household`.

| Question | fizzy's answer | Adopted here |
| :--- | :--- | :--- |
| Profile row without an email? | `users.identity_id` nullable, `unique [account_id, identity_id]`, `has_many :users, dependent: :nullify` | Yes — identical, as `family_members.user_id` |
| Credential | 6-char base32 magic code, 15 min, single-use via `destroy`; plus passkeys; plus bearer tokens for API | Magic code + passkeys; tokens deferred |
| No SMTP configured? | Sign-in code is readable in the container logs | Yes — replaces the recovery-code idea |
| Session expiry | No `expires_at` at all. Permanent cookie; the `sessions` row is the revocation point | Yes, revised — see below |
| Tenant vs. identity ordering | `require_account` before `require_authentication` (`# Checking and setting account must happen first`) | Yes |
| Untenanted actions | `disallow_account_scope` class method + `redirect_tenanted_request` guard | Yes — this is the `Household.none?` fix |
| Unknown email at sign-in | `redirect_to_fake_session_magic_link` builds an unsaved link so the flow is identical either way | Yes |
| Second adult joining | `Account::JoinCode` + `Identity::Joinable`, surfaced as a QR code | Yes |
| Profile changing owner | `Identity::Transferable` / `Identity::Transfer` | Yes |
| Security PIN | None. fizzy's `Pin` model is card-pinning, unrelated | No precedent — ours to own |
| Kiosk device pairing | None. `QrCodeLink` is a signed-URL-to-QR helper, not a device grant | No precedent — ours to own |

Two patterns worth lifting close to verbatim: `QrCodeLink` (26 lines, an `ActiveSupport::MessageVerifier` keyed off `key_generator.generate_key("qr_codes")` with a `:qr_code` purpose — it signs the URL, and a `qr_code_image` helper renders it through the `rqrcode` gem), and fizzy's dev-mode leak guard — an `after_action :ensure_development_magic_link_not_leaked` that **raises** if `flash[:magic_link_code]` is set outside `development`.

### Campfire and Writebook — the appliance references

**`FirstRun` is a model, and the guard lives in exactly one place.** Both apps have `app/models/first_run.rb`: a single `create!` that makes the account, the admin user, and seed content in one transaction-shaped call. The gate is one `before_action` in one dedicated controller:

```ruby
# campfire: app/controllers/first_runs_controller.rb
class FirstRunsController < ApplicationController
  allow_unauthenticated_access
  before_action :prevent_repeats
  # ...
  def prevent_repeats
    redirect_to root_url if Account.any?
  end
end
```

The lesson corrects this doc's earlier framing: `Account.any?` / `Household.exists?` is *not* the defect. **Scattering it across six unrelated call sites is the defect.** The appliance fix is to concentrate it in one `FirstRun`-style controller; the hosted fix is then `households.onboarded_at` on top. Do them in that order.

Worth noting in passing: both apps *seed* starter content (`DemoContent.create_manual`, a first room named "All Talk") rather than asking the user to supply it. FamilyPlates is already halfway there — its Recipes step offers `config/starter_recipes.yml` with every recipe pre-selected, and its Pantry step offers `PantryItem::DEFAULT_STAPLES` as a checklist, so both are confirm-or-uncheck screens rather than blank forms. What differs is that they are still two of the wizard's four steps instead of content seeded on completion and edited later. That trade is settled under "Not Doing" below and is out of scope here.

**Sliding session expiry, without a write per request.** This is the mechanism this doc needed and could not find in fizzy:

```ruby
# campfire: app/models/session.rb
class Session < ApplicationRecord
  ACTIVITY_REFRESH_RATE = 1.hour
  has_secure_token
  belongs_to :user
  before_create { self.last_active_at ||= Time.now }

  def resume(user_agent:, ip_address:)
    if last_active_at.before?(ACTIVITY_REFRESH_RATE.ago)
      update! user_agent:, ip_address:, last_active_at: Time.now
    end
  end
end
```

`last_active_at` is touched at most once an hour, so "active use silently extends the session" costs nothing. Schema is `token` (unique), `user_id`, `user_agent`, `ip_address`, `last_active_at`. Writebook's `Authentication::SessionLookup` is the matching two-line lookup.

**Join codes need a column, not a table.**

```ruby
# campfire: app/models/account/joinable.rb
before_create { self.join_code = generate_join_code }
def reset_join_code; update! join_code: generate_join_code; end
SecureRandom.alphanumeric(12).scan(/.{4}/).join("-")   # => "X4K9-2MPQ-7RTZ"
```

**Profile transfer needs no table either** — `signed_id` with a purpose and an expiry:

```ruby
# campfire: app/models/user/transferable.rb
TRANSFER_LINK_EXPIRY_DURATION = 4.hours
def transfer_id; signed_id(purpose: :transfer, expires_in: TRANSFER_LINK_EXPIRY_DURATION); end
def self.find_by_transfer_id(id); find_signed(id, purpose: :transfer); end
```

fizzy has fuller versions of both (`Account::JoinCode` with expiry, an `Identity::Transfer` model). For a household of five, Campfire's one-column and zero-table versions are the right size.

## Recommended Direction

Treat this as **the tenancy boundary, not a login screen**. The login form is the last 15% of the work; building it on top of today's scoping produces a login page in front of an app that still trusts an integer in a URL.

Adopt a **three-layer identity model** that maps onto what already exists:

| Layer | Question it answers | Mechanism |
| :--- | :--- | :--- |
| **Household identity** | Which family's data may this request see? | `User` via magic link or OAuth → reachable households |
| **Member identity** | Who is cooking right now? | One-tap profile pick, scoped to the authorized household |
| **Admin elevation** | May this person change the roster or settings? | PIN on a trusted device; fresh email session in hosted mode |

The PIN keeps its real job — keeping an eight-year-old out of Mum's admin panel on a shared tablet — and stops pretending to be an internet-facing security boundary. A 4-digit PIN against the existing throttle is roughly 50 hours to exhaust: fine as a speed bump, not fine as the only gate on `/admin`.

**The ordering constraint that governs everything below:**

> Every phase must be worth shipping to self-hosters even if the hosted business never happens.

That single rule sorts the roadmap. The IDOR fix, email login, account recovery, and kiosk pairing are all valuable to one family on a NAS. Multi-tenant onboarding, the `Household.none?` decoupling, and billing are worthless unless the hosted bet pays off — so they go last, and they are the only work that can be lost.

## Architecture Decisions

### Schema

```
users              id, email (unique, case-insensitive), verified_at, timestamps
identities         id, user_id, provider, uid, timestamps
                   unique [provider, uid]           # "email" | "google" | "apple" | "oidc"
sessions           id, user_id, token (unique), kind, user_agent, ip_address,
                   last_active_at, expires_at, timestamps
                   kind: "browser" | "kiosk"
households         + join_code (Campfire-style, resettable)
                   + onboarded_at
device_grants      id, user_code, device_code, household_id, approved_by_user_id,
                   expires_at, approved_at, timestamps

family_members     + user_id (nullable FK)
                   unique [household_id, user_id] where user_id is not null
```

This is not a novel design: fizzy's `users` table is `account_id` (not null) + `identity_id` (**nullable**) + `name` + `role` default `"member"` + `verified_at`, with a unique index on `[account_id, identity_id]`. Same shape, shipped.

**A nullable `family_members.user_id` replaces a `memberships` join table.** It says exactly what the product means — "any family member may attach an email" — and multi-household support falls out for free: a user with profiles in two households simply has two `family_member` rows. `user.family_members.map(&:household)` is the reachable set. Kids stay `user_id: nil` forever. There is no meaningful state where a user belongs to a household but has no profile, so the join table would only ever model something impossible.

**A separate `identities` table** lets one user attach email *and* Google *and* Apple to the same account, rather than creating a duplicate account per provider — the single most common OAuth bug.

**Primary keys: UUIDs. Decided.** Sequential integer IDs are what make `/set_profile/:id` enumeration cheap; fizzy uses UUID PKs throughout. Adopt UUIDs for `family_members` and `households` in **Phase 0**, before installs multiply and the migration gets expensive. This is defence in depth, not a substitute for the scoping fix — both ship in Phase 0. Note the knock-on: every existing `integer` FK to these tables migrates too, and `docs/architecture.md` ER diagram needs regenerating.

**No `join_codes` table and no `transfers` table.** A `join_code` column on `households` with a `reset_join_code` method (Campfire's `Account::Joinable`) covers inviting the second adult. Profile transfer uses `signed_id(purpose: :transfer, expires_in: 4.hours)` with no persistence at all (Campfire's `User::Transferable`).

### Sessions

**Confirmed: sliding expiry, 30 days idle / 90 days absolute.** Active use silently extends; a tablet untouched for a month re-verifies.

The implementation concern — "does this mean a database write on every request?" — is answered by Campfire's `ACTIVITY_REFRESH_RATE`: `last_active_at` is only touched when it is already more than an hour stale. So the sliding window costs at most one write per session per hour. Layer the two expiry checks on top of that `resume` call.

Kiosk sessions (`kind: "kiosk"`) are the exception: they do not expire, because a wall-mounted screen has nobody to re-authenticate it. They are restricted instead — no `/admin`, no household settings, even with a correct PIN — and revocable from a device list showing `user_agent`, `ip_address`, and `last_active_at`, with revoke-all.

Cookie carries `session.token` via `cookies.signed.permanent[:session_token]`; lookup is Writebook's two-line `Authentication::SessionLookup`.

### Deployment modes

A single config object, `FamilyPlates.config.mode`, read in a handful of places — not a fork.

* **`appliance`** (default): one household, open first-boot onboarding, `REQUIRE_LOGIN=false`, OAuth off. Today's UX is byte-identical unless the operator opts in.
* **`hosted`**: signup open, email verification required, tenant isolation enforced, OAuth available, billing hooks.

`REQUIRE_LOGIN` **must default to off**, because magic links assume working outbound SMTP and a large share of self-hosters running a container on a NAS have none and will not configure a mail relay for a meal planner.

**The no-SMTP fallback is to log the code.** fizzy documents this plainly: *"If email is not configured, you can still sign in by finding the 6-character verification code in your Docker container's logs."* This works only because the credential is a short typeable **code**, not solely a clickable link — so design it that way from the start. It needs no extra schema, no extra flow, and no second code path to rot, which makes it strictly better than a one-time recovery code generated at onboarding. Passkeys (Phase 3) and trusted forward-auth headers are the other two email-free paths.

### Credential choice — reopened

This doc previously listed passwords under "Not Doing". The reference apps split on exactly this line, so it is a live decision rather than a settled one:

* **Appliance mode**: Campfire and Writebook both use `has_secure_password`. A password needs no SMTP, no log-scraping, and no second delivery channel — which is the whole difficulty of magic codes on a NAS. The cost is a reset flow that itself needs email, or an admin-resets-it path.
* **Hosted mode**: fizzy's magic-code-plus-passkey approach is clearly right. Email is guaranteed to work, and there is no password to breach.

**Provisional recommendation:** magic codes as the primary credential in both modes, with the logged-code fallback for appliance installs, and passkeys added in Phase 3. But if the from-scratch no-SMTP install (see Key Assumptions) proves awkward, adopting `has_secure_password` for appliance mode is the proven path and should not be treated as a regression — two of the three reference apps do exactly that.

### Onboarding runs exactly once per household

Decided. `ensure_household_unconfigured` currently enforces once-per-*deployment* via `Household.exists?`, which is the same predicate as "does any tenant exist" — that conflation is defect #2. Replace it with a per-household completion flag (`households.onboarded_at`), so the wizard is idempotent per tenant and the deployment-level question disappears. In hosted mode a fresh household runs the wizard on first sign-in; in appliance mode behaviour is unchanged.

### User enumeration

Sign-in must behave identically for known and unknown email addresses. fizzy does this by constructing an unsaved `MagicLink` for unknown addresses (`redirect_to_fake_session_magic_link`) so response, redirect, and timing all match. Required before Phase 4 opens signup; cheap to build in at Phase 1.

### Joining and transferring

* **Join codes** (`Account::JoinCode` in fizzy): an admin generates a code, optionally shown as a QR, and a second adult redeems it to attach their email to a profile in that household. This is the answer to "how does the other parent get in" — it is not the same flow as kiosk pairing and should not be merged with it.
* **Identity transfer** (`Identity::Transferable`): reassigns a profile from one email to another, or from none to one. This is the kid-turns-thirteen case and the divorced-parent case. Cheap to add at Phase 1; expensive to retrofit once households have real history.

### Tenancy storage

**One SQLite database, `household_id` on every tenant-scoped row.** Confirmed — and on better grounds than this doc originally gave.

An earlier draft flagged "10,000 households / ~$500K ARR" as the point to re-examine SQLite. **That was wrong**: it treated a revenue milestone as a technical limit, and the write profile does not support it.

FamilyPlates is read-heavy with bursty, low-volume writes — a household plans meals once a week and checks off a grocery list once a week. At ~150 writes per household per week, with 30% of them landing in a Sunday-evening planning window:

| Households | Writes/week | Average | Sunday peak |
| ---: | ---: | ---: | ---: |
| 1,000 | 150,000 | 0.2/s | 4/s |
| 10,000 | 1,500,000 | 2.5/s | 42/s |
| 100,000 | 15,000,000 | 25/s | 417/s |

SQLite in WAL mode on NVMe sustains roughly 1,000–10,000 short write transactions per second. **Even 100,000 households sits an order of magnitude inside the envelope.** Throughput is not the constraint and is unlikely ever to be for this workload.

The real SQLite constraints here are **operational, not scale**:

1. **One slow write blocks every tenant.** A single writer per file means a long transaction — an HTTP call to a recipe site inside a transaction, a heavy grocery aggregation — stalls all households. This is a code-discipline problem that appears at 100 households as readily as 100,000. Keep transactions short and never do I/O inside one.
2. **Migrations lock everyone.** One `ALTER TABLE` pauses all tenants at once.
3. **Backup and restore are all-or-nothing.** No per-family export, no restoring one household to a point in time.
4. **Vertical scaling only**, and a single-file blast radius.

**The design change that removes even these: one SQLite database per household.** Rails 8 has first-class multi-database support and this app already uses it — `config/database.yml` runs four separate SQLite databases in production (primary, cache, queue, cable). The machinery is in use today.

Per-household databases via `connects_to` / `connected_to(shard:)` would give:

* Write concurrency becomes N independent writers rather than one.
* Migrations roll per tenant, progressively; a failure affects one family.
* Backup, export, and GDPR erasure become file operations.
* Blast radius is one household.
* **Isolation by construction** — this is the big one. A missing `household_id` scope cannot leak across families when the data is not in the same file. Tenant resolution happens *once per request* instead of scoping being re-derived at 87 call sites, which cuts the attack surface from 87 places to one.

Costs: a tenant resolver and connection-management layer, cross-tenant queries (ops dashboards, billing reconciliation, analytics) needing a shared database or fan-out, migration orchestration across N files, and connection-pool tuning.

**Recommendation: stay on one database with `household_id`, and do not treat per-tenant databases as a scaling fallback — treat them as an isolation upgrade available at any time.** The conversion is a mechanical split script, so deferring costs little. The triggers for revisiting are *not* revenue or customer count; they are:

* a slow-write incident that degrades all tenants at once,
* a real need for per-family export or point-in-time restore (a support or compliance request), or
* migration windows becoming unacceptable.

Worth noting that the appliance mode is already database-per-tenant taken to its limit — one install, one family, one file — which is exactly what Campfire and Writebook are.

### Isolation enforcement

Scoped associations everywhere (`current_household.family_members.find(...)`, never `FamilyMember.find(...)`), plus a **generated cross-tenant request test**: build two households, then assert every member-scoped route returns 404 for the other household's IDs, enumerating from `Rails.application.routes.routes`. Discipline across 87 call sites and every future one is precisely the failure mode to expect; the harness is what makes the invariant hold.

### Billing (Phase 5)

Appliance mode has no billing code at all — that is the point of the mode flag, and the payment gem should not load outside hosted mode.

| Option | Take | Who owes the tax |
| :--- | :--- | :--- |
| **[Pay gem](https://github.com/pay-rails/pay)** (v11.6.x, Rails 6+) | provider's | wraps Stripe / Paddle Billing / Braintree / Lemon Squeezy behind one API |
| **Stripe Billing + Stripe Tax** | ~2.9% + 30¢ | **you** — you register and remit VAT/GST/sales tax per jurisdiction; Stripe calculates and assists registration |
| **Merchant of Record** — Paddle, Lemon Squeezy, [Polar](https://polar.sh) | ~5% + fees | **them** — they are the legal seller and handle global registration and remittance |

**Recommendation: the Pay gem, pointed at Stripe.** `Household include Pay::Billable`. The reasoning is not that Stripe is best — it is that the merchant-of-record question cannot be answered before you know which countries your customers are in, and Pay turns that later switch into a configuration change instead of a rewrite. Revisit MoR if non-domestic revenue becomes material.

**Pay gem trust assessment.** MIT, ~2.0M total downloads, v11.7.2 released 2026-08-23, maintained by Chris Oliver (GoRails), Jason Charnes, and Collin Jilbert. Actively released, well-known Rails-community maintainers, and it exposes the underlying provider objects so you are never fully boxed in by the abstraction. Two honest caveats: it is community-maintained with a bus factor around three (no company behind it), and eleven major versions means it has a history of breaking upgrades — budget for migration work between majors.

**Terms used below.** *MoR (Merchant of Record)* — the legal entity that sells to the customer and is therefore responsible for collecting and remitting VAT/GST/sales tax in every jurisdiction. With Stripe that is us; with Paddle, Lemon Squeezy, or Polar it is them, for roughly 5% + 50¢ instead of 2.9% + 30¢. *LTV (Lifetime Value)* — total net revenue one customer produces before cancelling, calculated as net revenue per period ÷ churn rate per period. LTV is the ceiling on what may be spent acquiring a customer.

### Pricing — $4/month, or $35/year

**Decided: $4/month, $35/year (27% discount).** With the annual price fixed at $35, $4 is the only whole-dollar monthly price that yields a sensible discount — $3/mo makes the annual plan a 3% saving (pointless) and $5/mo puts it back at 42%.

**Sensitivity, not a recommendation.** This fixes the discount *ratio* by lowering the monthly price rather than raising the annual one. Against the earlier $5/$36 pairing at a 70/30 mix that is −$8,400/yr at 1,000 subscribers and −$84,000/yr at 10,000; a $5/$50 pairing would be roughly +$41,000/yr at 10,000.

**Read those numbers with their assumption attached: they hold subscriber count constant across prices, which cannot be true.** The $5/$50 pairing only wins if charging 43% more for the annual plan costs fewer than ~30% of conversions. There is no evidence either way, so this is a sensitivity analysis, not an argument for a higher price.

**The omitted factor is the free tier.** Every hosted subscriber is someone who chose not to run the container themselves, so what is being sold is convenience-over-self-hosting — and that caps price far harder than processor fees do. The pressure is also asymmetric: a customer who balks at the price does not churn to a competitor, they self-host, and the project absorbs support load with no revenue attached.

**Conclusion: $4/$35 is in the right band; ship it and revisit with data.** At the subscriber counts that will actually occur first, this whole comparison is noise — $35 against $50 at 100 subscribers is about $1,400/yr. Pricing is also the cheapest decision in this document to reverse: a config change plus grandfathering, against schema and tenancy decisions that are not. Raise prices when conversion and churn data exist, not before.

Second-order effect worth knowing: **lowering the monthly price raises the effective fee rate**, because Stripe's fixed 30¢ is a larger share of a smaller charge — 8.9% at $5/mo, **10.4% at $4/mo**, 12.9% at $3/mo.

### Revenue forecast — $4/mo, or $35/yr

Per customer, per year, before any running costs:

| Plan | Txns/yr | Gross | Stripe fees | Net | Effective |
| :--- | ---: | ---: | ---: | ---: | ---: |
| Monthly $4 | 12 | $48.00 | $4.99 | **$43.01** | 10.4% |
| Annual $35 | 1 | $35.00 | $1.32 | **$33.69** | 3.8% |

Net annual revenue by steady-state subscriber count, Stripe:

| Mix | 100 | 1,000 | 10,000 |
| :--- | ---: | ---: | ---: |
| 100% monthly | $4,301 | $43,008 | $430,080 |
| 70/30 monthly/annual | $4,021 | $40,211 | $402,111 |
| 50/50 | $3,835 | $38,347 | $383,465 |
| 100% annual | $3,368 | $33,685 | $336,850 |

Moving one customer from monthly to annual now costs **$9.32/yr** in net revenue, down from $20.00 under the $5/$36 pairing. Switching Stripe to a merchant of record costs roughly $3.60/yr on the same customer — so the discount is still the larger lever, but no longer by 5×.

Annual billing also reduces churn and involuntary failed-payment loss, neither of which this model captures, so the real gap is narrower than the table implies.

Excluded from all of the above: churn, refunds, failed payments, VAT/sales tax, and every running cost. At 10,000 subscribers churn dominates everything in this table — that is a flow, not a headcount, and no pricing decision survives contact with a 5%/month churn rate.

**Decide the billing period before the provider.**

## Phased Plan

**Phase 0 — Isolation. No new UI.**
Scope `set_profile` to an authorized household. Delete the `Household.first` fallback and let `current_household` return `nil` when unauthenticated. Scope the ActionCable connection. Migrate `households` and `family_members` to UUID primary keys. Consolidate the six scattered `Household.none?` checks into a single Campfire-style `FirstRun` guard. Add the cross-tenant test harness. Ships independently as a patch release.

**Phase 1 — Identity, opt-in.**
`users`, `identities`, `sessions`, `family_members.user_id`. Magic codes (6 chars, 15 min, single-use, logged when SMTP is absent). Join code on `households` and `signed_id` profile transfer. Enumeration-safe sign-in. Sign in → land on your own profile by default → one-tap switch to any other profile in the household → PIN for admin profiles. Sliding 30/90 sessions with Campfire's throttled `last_active_at`, plus a device list. `households.onboarded_at`. `REQUIRE_LOGIN=false` by default.

**Phase 2 — Kiosk pairing.**
RFC 8628 device authorization grant, built generically. Kiosk displays a QR code; an already-signed-in phone scans and approves; the kiosk receives a non-expiring restricted session. The same primitive covers "add my phone" and "sign in the laptop" — build it kiosk-specific and it gets built twice.

**Phase 3 — OAuth, both flavors, both off by default.**
Passkeys first — fizzy treats them as a peer of magic links, and they are the strongest email-free path. Then Google and Apple for the hosted product (consumer identity), and generic OIDC plus trusted forward-auth headers for self-hosters, who already run Authelia, Authentik, or Tailscale in front of things and will be annoyed by a Google-only button. Forward-auth is also the escape hatch for operators with no SMTP.

**Phase 4 — Hosted mode.**
Split `FamilyPlates.installed?` from `Current.household.present?` across the six conflated call sites, using fizzy's `disallow_account_scope` / `redirect_tenanted_request` pattern to make "runs outside a tenant" a declaration rather than a convention. Resolve the tenant *before* the identity. That rename *is* most of the multi-tenant conversion. Open signup, email verification, per-tenant onboarding.

**Phase 5 — Subscriptions.**

## Key Assumptions to Validate

- [ ] **The hosted business exists at all.** Currently unvalidated. Test: the phasing above is designed so this can be discovered false at Phase 3 with nothing lost — every prior phase stands on its own for self-hosters.
- [ ] **Self-hosters will accept an email gate.** Test: ship Phase 1 with `REQUIRE_LOGIN=false` and measure how many operators turn it on. If nobody does, the hosted bet weakens considerably.
- [ ] **Magic codes are deliverable in practice.** Largely retired as a risk: fizzy ships "read the code from the container logs" as its documented no-SMTP path. Test: a from-scratch Docker install with no SMTP, signing in via the logged code, and confirm the log line is findable without knowing the codebase.
- [ ] **One SQLite DB carries multi-tenant load.** Test: seed 500 households with realistic recipe and meal-plan volume, profile the planner and grocery-list queries under WAL.
- [ ] **Isolation actually holds.** Test: the generated cross-tenant route suite must pass with zero exemptions before Phase 4 opens signup.
- [ ] **30/90 sliding expiry does not annoy real households.** Test: instrument how often a re-auth is actually triggered once a household is live. If the fridge tablet re-verifies monthly and that is unwelcome, `kind: "kiosk"` is the escape hatch rather than lengthening the window for everyone.
- [ ] **The one-tap kitchen-tablet experience is worth protecting.** Currently 100% untested; it is an assumption about the product's value, not an established strength. Test: confirm any real household uses profile switching at all before optimising further around it.
- [ ] **Nobody is relying on the current cookie-only session.** Test: confirm the Phase 0 removal of the `Household.first` fallback does not break unauthenticated views (navbar, landing, onboarding).

## MVP Scope

**In — Phase 0 and Phase 1 together:**
* Household-scoped profile selection; no global `FamilyMember.find` on user input.
* `Household.first` fallback removed; `current_household` may be `nil`.
* Cross-tenant request test harness.
* `users` / `identities` / `sessions` and `family_members.user_id`.
* Magic-link sign-in, email verification, sliding 30/90-day sessions.
* Sign-in defaults to your own profile; one-tap switch within the household; PIN unchanged for admins.
* `REQUIRE_LOGIN` flag, default off — appliance UX unchanged.

**Out of MVP:** kiosk QR pairing, any OAuth provider, hosted mode, open signup, billing.

## Not Doing (and Why)

* **A one-time recovery code at onboarding** — superseded. Logging the sign-in code covers the no-SMTP case with no extra schema or second code path.
* **Merging kiosk pairing with join codes** — they look similar (both QR, both pair a thing to a household) and have different trust models: a join code grants a person ongoing access, a device grant gives a fixed screen a restricted session. Merging them produces a flow that is wrong for both.
* **Passwords in hosted mode** — a password column buys a reset flow, a strength policy, a credential-stuffing surface, and breach liability, in exchange for nothing magic codes don't already provide. *For appliance mode this is reopened — see "Credential choice".*
* **A `memberships` join table** — a nullable `family_members.user_id` expresses the same model with one column and no impossible states.
* **A `join_codes` table or a `transfers` table** — Campfire does both with one column and one `signed_id` respectively.
* **Collapsing the recipes and pantry onboarding steps** — considered and **rejected**. Both appliance reference apps seed demo content instead of asking, but the two steps stay distinct here: they teach two different concepts (what you cook vs. what you already have), and the pantry step is what makes the grocery list useful on day one. Seeding *defaults within* each step turned out to be done already — both steps ship curated, pre-ticked defaults — so that sub-question is closed too. Merging the steps remains rejected.
* **Requiring an email per family member** — kids and shared tablets must stay one-tap. Email is opt-in, per member, forever.
* **PIN as the internet-facing gate** — 4 digits is a speed bump for a shared kitchen tablet, not an authentication boundary. In hosted mode `/admin` requires a fresh email session.
* **Subdomain-per-tenant routing** — session-resolved tenancy is sufficient at this scale and avoids wildcard DNS and certificate complexity.
* **RBAC beyond `admin` / `member`** — the binary role decision from the prior idea doc still holds.
* **2FA / TOTP** — magic links and OAuth already avoid a reusable shared secret. Revisit only if the hosted product stores payment data.
* **Postgres for the hosted tier** — maintaining two database targets and two migration paths forever is a heavier tax than the SQLite ceiling is likely to impose.
* **Apple Sign-In before it's paid for** — requires a $99/yr developer account and mandatory Hide-My-Email relay support. Google first.

## Open Questions

* ~~Which subscription provider?~~ **Provisionally the Pay gem pointed at Stripe** — see Billing above. Sub-question still open: per-household flat pricing or per-seat, which changes what `households` must store.
* ~~Does `REQUIRE_LOGIN=true` still allow the PIN-less one-tap picker?~~ **Decided: yes.** The household session covers the device; members stay one-tap; admins still need a PIN.
* ~~Account recovery when a self-hoster loses email access and their session?~~ **Decided: the sign-in code is logged**, per fizzy. Remaining sub-question: is a `bin/rails` console task also warranted for the case where logs have rotated?
* **Credential choice for appliance mode** is the one genuinely open decision left: magic codes with a logged fallback, or `has_secure_password` as both appliance reference apps do. Resolve by attempting the no-SMTP install before Phase 1 schema work.
* Willingness to pay is entirely unmeasured, and the free self-hosted tier is the real competitor. Cheapest test: a pricing page with an email capture before any billing code is written.
* Per-household flat pricing or per-seat — changes what `households` must store.
* ~~Should `docs/architecture.md:44` be corrected now, or as part of Phase 1?~~ **Done upstream.** `docs/architecture.md:41-42` now records that there is no `User` model and that PINs are bcrypt digests. The one leftover is the ER diagram at `docs/architecture.md:23`, which still draws a `User` entity — fold that into the regeneration the UUID migration already requires.
