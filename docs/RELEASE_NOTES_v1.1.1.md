# FamilyPlates v1.1.1 — security patch

**Upgrade now if you are running `ghcr.io/elevate08/familyplates:v1.1.0` or
`:latest` pulled before this release.** Three of the defects below are reachable
by anyone who can open the app in a browser, with no password, no PIN, and no
account. If your instance is exposed beyond your own LAN, treat it as
compromised: after upgrading, change every organizer PIN and review your family
roster for profiles you did not create.

This release contains **no database migration**.

## Fixed

### The shipped compose file used a publicly known secret key

`docker-compose.yml` defaulted `SECRET_KEY_BASE` to a fixed string that is
published in this repository, and both the README and the getting-started guide
printed that same string on the line you copy. That value signs the cookie
saying which family member you are, so **anyone who knew it could forge an
organizer session** without a PIN and without touching any part of the app.

Compose now refuses to start without a real key, and the app refuses to boot on a
known placeholder or anything under 32 characters.

> **If you deployed without setting `SECRET_KEY_BASE` yourself, treat the install
> as compromised.** Generate a key with `openssl rand -hex 64`, set it, restart,
> and review your family roster for profiles you did not create. Everyone will be
> signed out — that is the point.


### Anyone could make themselves an organizer (no credentials required)

Two separate paths, either of which gave a stranger full admin:

- Every `/onboarding/*` step stayed open on a fully configured install. A single
  request could add a new **admin** profile with an attacker-chosen PIN, which
  they then selected from the normal profile screen.
- Roster editing was exposed outside the admin area with no permission check, so
  an organizer's PIN could simply be overwritten. Member profiles have no PIN by
  design, so an attacker took a member profile first and proceeded from there.

Roster changes now happen only in the Admin Control Center, and the setup wizard
is closed once your kitchen is configured.

### Organizer PINs could be guessed without limit

A 4-digit PIN is 10,000 possibilities and nothing was counting attempts. PIN
entry is now rate limited per address and per profile, and PINs are compared in
constant time.

### Recipe import could be pointed at your private network

Importing a recipe fetched any URL it was given, including addresses inside your
home network, your Docker network, and cloud metadata services. Imports are now
restricted to public web addresses, re-checked on every redirect, and capped in
size.

### Recipe and ingredient text could run scripts in your browser

Recipe titles, tags, ingredient names and pantry icons were inserted into pages
as markup rather than text. Since recipe import copies these fields from
third-party sites, a hostile recipe page could run code in your browser. All of
these are now inserted as text.

## Also fixed

- **The monthly calendar dropped part of the current week.** When a week
  straddled a month boundary the calendar and its print-out showed only one
  month, hiding the rest of the current week. It now shows whichever month holds
  most of the week.
- **Pantry items went missing from shopping lists.** Ingredients were matched
  against pantry staples by substring, so "Peanut butter", "Buttermilk", "Rice
  vinegar", "Brown rice", "Pasta sauce" and similar were treated as already in
  the pantry and left off the list. Matching is now exact. One deliberate change:
  "Kosher salt" no longer matches a "Salt" staple — add it to your pantry if you
  want it treated as one.
- **Adding a pantry item with a blank or duplicate name returned an error page.**
  It now shows the validation message.
- **Re-running the setup wizard's pantry step reset customizations.** Hand-picked
  aisles and icons are now preserved.
- **Signing in after a session expired could land on a broken page.**
- **Recipe import of an unreachable link created a blank placeholder recipe**
  instead of reporting the failure.

## Still outstanding, planned for v1.2.0

- PINs and Google service-account credentials are still stored unencrypted. Both
  need a database migration, which does not belong in an emergency patch. If you
  have configured Google Calendar, note that the saved credential has been
  rendered back into the settings page on every visit; **rotate that key**.
- No Content Security Policy is sent yet.

## Verification

236 tests passing; RuboCop, Brakeman, bundler-audit and importmap audit all
clean. Container publishing is now gated on that suite — v1.1.0 was released
with a failing test because nothing connected the two.
