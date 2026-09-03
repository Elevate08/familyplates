# FamilyPlates v1.2.0 — security, correctness and performance

**Upgrade now if you are running `ghcr.io/elevate08/familyplates:v1.1.0` or a
`:latest` pulled before this release.** Several defects below are reachable by
anyone who can open the app in a browser — no password, no PIN, no account. If
your instance is reachable beyond your own LAN, treat it as compromised: after
upgrading, change every organizer PIN and review your family roster for profiles
you did not create.

**This release contains four database migrations.** They run automatically on
first boot (`bin/docker-entrypoint` calls `rails db:prepare`). Back up your
SQLite volume before upgrading, as you would for any schema change.

## Before you upgrade

### 1. Set your own `SECRET_KEY_BASE` (required)

The shipped `docker-compose.yml` defaulted this to
`replace_with_a_secure_random_hex_string` — a literal published in this
repository — and the README printed it on the line operators copy. That value
signs the session cookie the app trusts to identify you, so **anyone who read the
repo could forge an organizer session on an install that kept the default.**

```bash
openssl rand -hex 64   # SECRET_KEY_BASE
```

The app now **refuses to boot** on that known value rather than starting
insecurely. Changing it signs everyone out, which is the intended effect.

### 2. Set the encryption keys (required if you use Google Calendar sync)

```bash
openssl rand -hex 32   # ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
openssl rand -hex 32   # ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
```

These must not change once set, or the stored credential becomes unreadable.
They are deliberately separate from `SECRET_KEY_BASE`, so rotating that does not
destroy them.

### 3. Rotate your Google service-account key

Up to this release the private key was stored in clear text **and rendered back
into the admin settings page on every visit**. Rotate it at Google regardless of
who you think has seen it.

## Fixed

### Reachable without any credentials

- **Forgeable organizer sessions** from the published default secret key (above).
- **Anyone signed in could make themselves an organizer.** The onboarding wizard
  permitted `role`, bypassing the admin controller entirely.
- **The setup wizard stayed open on configured installs.** Authentication
  exempted anything under `/onboarding` by path, leaving the roster, recipe and
  pantry steps reachable with no session at all.
- **Organizer PINs could be guessed without limit.** PIN entry is now rate
  limited per IP *and* per profile, across both entry paths.
- **Recipe import could be pointed at your private network.** Imports are now
  checked by *resolved address* — every DNS answer against explicit v4/v6
  denylists, the address pinned so nothing re-resolves between check and connect,
  every redirect hop re-checked, redirects capped, and the body streamed to a
  2 MB ceiling.
- **Recipe, ingredient and pantry text could run scripts in your browser.** Eight
  injection sinks rebuilt, including a server-side one that put your own pantry
  icon text straight into the page. A Content Security Policy is now sent — it
  was commented out end to end, which is what made these directly exploitable.

### Stored secrets

- **Organizer PINs are stored as bcrypt digests**, not plaintext, and compared in
  constant time. Two migrations add the digest and drop the plaintext column.
- **Google service-account JSON is encrypted at rest** and never returned to the
  page. The field shows whether a key is stored; blank means "keep it".

### Correctness

- The month calendar no longer drops the tail of a week that straddles a month
  boundary.
- Moving a meal slot happens in one transaction — a failed move no longer
  destroys the original.
- Pantry staples match exactly instead of by substring, so "Rice vinegar" is no
  longer treated as "Rice".
- Re-running the setup wizard keeps pantry aisles and icons you chose.
- Invalid pantry submissions show errors instead of returning a 500.
- Importing an unreachable link reports the failure instead of creating a blank
  placeholder recipe.
- A renamed ingredient re-syncs its old aisle mapping.
- Ingredient rows added in quick succession keep their own names, and typing is
  no longer interrupted by a focus jump landing a moment late.

### Speed

- Saving a 15-ingredient recipe: **211 queries → 91**.
- Grocery auto-fulfilment: **37 queries → 14**.
- A 20-ingredient edit page: **455 KB → 235 KB**.

### Accessibility

- **Pinch-zoom works again** — `maximum-scale=1` and `user-scalable=no` are gone
  (WCAG 1.4.4).
- Every form field has a label that points at it, dropdowns are keyboard
  navigable, and scrollable menus stay out of the tab order.

## New

- **The version is shown on the admin dashboard**, top right. Quote it when
  reporting a problem.

## Verification

324 tests and 34 browser tests passing; RuboCop, Brakeman, `bundler-audit` and
`importmap audit` clean. Every fix was confirmed *failing* against the pre-fix
code before it landed. Container publishing is gated on that suite — v1.1.0 was
published with a failing test because nothing connected the two.

Migrations were verified rolling back and re-applying.

## Known limitations

- Pinch-zoom and safe-area insets are asserted by test but have not been checked
  on a physical phone.
- `current_household` still falls back to "the first household" in a few places.
  Harmless on a single-household install, which is every supported install today.
