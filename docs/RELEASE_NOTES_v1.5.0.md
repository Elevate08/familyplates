# FamilyPlates v1.5.0 — Hearth, and a weekday you shop

The kitchen is warm oat and cream, with terracotta actions and forest
success states. Household & Meal Schedule asks which weekday you shop
when the household shops every week or every two weeks, instead of a
calendar date.

**No database migration.** This release does not add or rewrite tables.
Replace the image on the same volume. If you run the recipe-import
worker, update that container to the same image.

## Before you upgrade

### Shopping day

Households already set to shop weekly on Saturday stay on Saturday. The
stored day is left alone until an organizer changes it under Household
& Meal Schedule. Every month still asks for a day of the month (1st–31st);
a 29th, 30th or 31st falls on the last day of a shorter month.

Every 2 weeks keeps the same weekday every other week. Changing that
weekday slides the existing 14-day rhythm by a few days. Leaving the
weekday as it is does not move the period.

### Headings

Headings use Lora, loaded from Google Fonts. The app's Content Security
Policy allows `fonts.googleapis.com` and `fonts.gstatic.com`. Offline, or
if a proxy blocks those hosts, headings use Georgia. Cook Mode stays dark.

### What stays the same

- **Prices, routes and behaviour are unchanged.** The hosted service is
  still a 14-day trial, then $5/month or $50/year. The appliance is still
  free.
- **Each family member's accent colour still recolours buttons and
  highlights.** The default for a new profile is terracotta, and Terracotta
  and Forest join the colour choices. Colours already saved on a profile
  stay as they are.

## New

- **Hearth.** Pages sit on warm oat, cards are cream with thin warm
  borders, primary actions are terracotta and success states forest green.
  Dark mode is a warm charcoal and still follows the theme toggle. The
  installed app's theme colour is terracotta (`#A64730`).
- **A weekday you shop.** Every week, the grocery list runs from that
  weekday to the day before it next week. Every 2 weeks uses that weekday
  every other week.

## Verification

The version constant, the `VERSION` file and this changelog's newest
heading agree on 1.5.0. CI runs the unit, system and Playwright suites
for both editions, along with RuboCop, Brakeman, `bundler-audit` and
`importmap audit`.

The full changelog is in [CHANGELOG.md](https://github.com/Elevate08/familyplates/blob/master/CHANGELOG.md#v150---2026-10-15).
