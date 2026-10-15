# FamilyPlates v1.3.0 — two editions, accounts and Cook Mode

FamilyPlates now comes in two editions from one codebase: the free self-hosted
**appliance**, and a **hosted service** with Stripe billing and a private
operator console. The hosted service's code lives in a `saas/` engine that
appliance builds don't contain. Sign-in, sessions and device pairing were
rebuilt for multiple households, and every route is now tested against every
kind of visitor.

**This release rewrites core tables.** Household and family-member IDs move from
integers to UUIDs. Migrations run automatically on first boot
(`bin/docker-entrypoint` calls `rails db:prepare`). **Back up your SQLite volume
before upgrading.**

FamilyPlates is now under the [O'Saasy License](https://github.com/Elevate08/familyplates/blob/master/LICENSE.md): MIT plus one
condition, that you may not offer FamilyPlates to others as a competing hosted
service. Self-hosting, modifying and sharing it stay free.

## Before you upgrade

### 1. Back up the database (required)

Household and family-member IDs move from integers to UUIDs, along with the
seven foreign keys that point at them. The migration keeps every relationship
and has a tested rollback, but it rewrites core tables.

### 2. Move off Google Calendar direct sync

Direct sync is gone, and the migration drops the stored service-account
settings. Use the calendar subscription feeds (`.ics`/`webcal`) instead.

### 3. Check your recipe links

Recipe source and image links must be `http` or `https`. A recipe whose link
uses another scheme, such as `data:`, has to have that link fixed before it can
be saved again. The URL importer only fetches from ports 80, 443, 8080 and 8443.

### What stays the same

- **Existing sessions keep working.** Session tokens are hashed in place, so
  nobody is signed out. Rolling back that migration clears sessions, because the
  hashes can't be reversed.
- **Appliance mode is unchanged.** Signing in stays opt-in: `REQUIRE_LOGIN` can
  only be turned on once at least one admin profile has a linked account with a
  password.
- **The published image is the appliance, and it refuses hosted mode.**
  `FAMILYPLATES_MODE=hosted` needs the hosted edition, built with
  `--build-arg EDITION=hosted`. An appliance image started in hosted mode stops
  at once with `HostedEditionMissingError`.
- **Profile transfer links made before the upgrade stop working.** Ask for a new
  link.

### Hosted operators only

- Hosted mode refuses to boot without `APP_HOST` and `SMTP_ADDRESS`, and forces
  HTTPS by default: set `FORCE_SSL` to override, or `ASSUME_SSL` behind a
  TLS-terminating proxy.
- Hosted production ignores Stripe test-mode webhooks. Set
  `STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS=true`, or the same key in credentials, to
  accept them.

## New

- **Two editions** ([docs/editions.md](https://github.com/Elevate08/familyplates/blob/master/docs/editions.md)). Billing, the operator
  console, public sign-up, support conversations and deletion requests live in a
  `saas/` Rails engine, loaded only by `Gemfile.saas` when
  `FAMILYPLATES_MODE=hosted`. The appliance image doesn't contain `saas/`, and
  its Content Security Policy doesn't allow Stripe.
- **Cook Mode:** a distraction-free, step-by-step kitchen screen with countdown
  timers, an ingredient drawer and a screen wake lock. `/cook` opens whichever
  meal is due by the household's own serving times.
- **Calendar subscriptions** (`.ics`/`webcal`) with one-tap setup for Apple,
  Google and Outlook.
- **Accounts separate from household profiles**, so one person can belong to
  several households. Passkeys, sign-in with Google, Apple, generic OIDC or a
  trusted forward-auth proxy, and kiosk device pairing (RFC 8628) with a
  connected-devices list and revocation.
- **Leftovers and low staples.** A cooked meal feeds later slots until it runs
  out or passes its shelf life; pantry staples flagged as running low join the
  grocery list and are restocked when ticked off.
- **Recipe import works on more sites**, including ones behind Cloudflare's bot
  challenge such as The Mediterranean Dish, and Allrecipes, Serious Eats and
  Simply Recipes. When a site turns the importer away, it tries once more with
  an honest FamilyPlates user agent, through the same outbound URL checks.
- **Hosted service:** public sign-up, Stripe billing (14-day trial, $5/month or
  $50/year), and an operator console at `/platform_admin` behind its own
  password, TOTP and rate limit.

## Fixed

### Security

- A meal slot accepted any household's recipe ID, so one household could read
  another's recipe. Fixed along with the other cross-tenant gaps a new
  route-by-role authorization table found.
- Anonymous requests no longer resolve to the installation's household.
- When login is required, a profile cookie on its own no longer opens the app,
  and signing into a different account drops the previous profile.
- Session tokens are stored as SHA-256 hashes; pairing codes, transfer links and
  operator authenticator codes work once.
- A blank organizer PIN at sign-up is no longer stored as `1234`. Uploaded images
  must be real images under 8 MB, and calendar feeds can't be cached publicly.
- The URL importer refuses more internal addresses: IPv4-compatible IPv6, 6to4,
  site-local and other reserved ranges, and non-standard ports.

### Correctness

- **The Docker image hadn't built since passkeys arrived**, and **production
  didn't boot at all** (`NameError` in a production-only deploy check). Both
  editions build and boot again, and CI now proves it on every change.
- A bad `?week=` or `?month=` parameter no longer causes a server error.
- A calendar feed no longer drops a meal titled "No Meal Planned".
- 27 tests that failed on Mondays and Tuesdays are fixed.

### Accessibility

- Every page is checked with axe for every kind of visitor. Icon-only buttons,
  colour swatches, grocery checkboxes and form fields are named, and the cook and
  print layouts declare their language.

## Removed

- Google Calendar direct sync (use subscription feeds).
- The `hosted:simulate_customers` and `scale:validate` development rake tasks,
  dead code, and the stock Kamal scaffold `config/deploy.yml`.

## Verification

Unit, system and Playwright suites pass for both editions, along with RuboCop,
Brakeman, `bundler-audit` and `importmap audit`. CI builds both images, checks
that the appliance image has no hosted code and refuses hosted mode, and that
the hosted image boots. Container publishing is gated on that suite.

The full changelog is in [CHANGELOG.md](https://github.com/Elevate08/familyplates/blob/master/CHANGELOG.md#v130---2026-10-11).
