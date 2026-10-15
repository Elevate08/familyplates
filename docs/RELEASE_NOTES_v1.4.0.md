# FamilyPlates v1.4.0 — grocery lists that match how you shop

The grocery list is no longer stuck on this week. A household can open any
stretch of days up to 42, set how often it shops, and tick items off on one
phone while another sees the same list. The hosted service is a 14-day trial,
then **$5/month or $50/year**.

Migrations run on boot. They add tables and columns; they do not rewrite the
UUID conversion from v1.3.0. **Back up your SQLite volume before upgrading.**

## Before you upgrade

### 1. Run the recipe-import worker

Pasting a recipe link now queues a job and shows a waiting page. The job runs
in a second container, capped at 512 MB, so a page you do not control cannot
exhaust the web server. Use the `worker` service in `docker-compose.yml`, or
the extra `docker run` in the [getting started guide](https://github.com/Elevate08/familyplates/blob/master/docs/getting-started.md).
It shares the web container's image, volume and settings. Without it, imports
stay queued and the waiting page says import is busy. Start the worker after
the web container is up. On the hosted service each destination has a `job`
role (`bin/jobs`, 512 MB).

### 2. Appliances behind a reverse proxy

Set `TRUSTED_PROXIES` to your proxy's single address, as the app container
sees it. Ranges are refused at boot. Until you set it, and only while
forward-auth is on, the single addresses in `FORWARD_AUTH_TRUSTED_PROXIES`
are used instead. The image keeps Puma on loopback inside the container
(`BINDING=127.0.0.1`); reach the app on port 80.

Forward-auth reads `Remote-Email` and `Remote-Name`, and no user ID header
unless you set one. **Authelia:** `FORWARD_AUTH_USER_HEADERS=Remote-User`.
**oauth2-proxy:** `FORWARD_AUTH_EMAIL_HEADERS=X-Forwarded-Email` and
`FORWARD_AUTH_USER_HEADERS=X-Forwarded-User`. If you skip the user ID header,
each person gets a second forward-auth identity, keyed by email, the first
time they sign in. It is the same account. `FORWARD_AUTH_TRUSTED_PROXIES`
must be the proxy's own address, not a LAN range. Details are in
[Getting started](https://github.com/Elevate08/familyplates/blob/master/docs/getting-started.md).

### 3. Sign-in providers

Sign in with Apple is removed. Leftover `AUTH_APPLE_*` settings are ignored.
Google, and OIDC on the hosted service, must report the email as verified.
OIDC needs `OIDC_ISSUER` (and `OIDC_JWKS_URL` when there is no discovery
document).

### What stays the same

- **The appliance is still free**, and the published image is still the
  appliance. It refuses hosted mode.
- **Existing households shop weekly on Saturday** until an organizer changes
  that under Household & Meal Schedule.
- **Ticks already stored only in a browser are not copied over.** The list
  starts unticked; new ticks are shared from then on.

## New

- **Any date range, up to 42 days.** This week, Next week, From today, This
  month, Next month, your own dates, and previous/next arrows (a whole month
  when the list covers one calendar month). The planner's week and month
  views link to the grocery list for the period they show. A period you have
  opened works offline.
- **A shopping schedule.** Organizers choose every week, every 2 weeks, or
  every month, and the day the household shops. The Groceries tab opens on
  the current shopping period. This shop and Next shop step through those
  periods.
- **Shared grocery ticks.** Tick an item on one device and the same list
  shows it ticked on the others. Only organizers can tick or Reset; everyone
  else sees the list read-only. Reset clears it for the household. A tick
  made offline is sent when the device is back, and the later change wins.
- **Hosted pricing: 14-day trial, $5/month or $50/year.** Checkout asks the
  billing owner to agree to the renewal terms for that price. Stripe price
  IDs are unchanged.

## Fixed

- **A recipe planned on several days was counted once.** Every cooked meal
  adds its ingredients. Leftover meals still add nothing.
- A date parameter longer than 128 characters on the grocery list or the
  planner no longer causes a server error.
- `/grocery_list/<plan number>` opens the grocery list for that plan's week.
- Active Storage's direct-upload endpoint no longer accepts anonymous
  uploads. Recipe photos still upload through the recipe form.

## Verification

Unit, system and Playwright suites pass for both editions, along with
RuboCop, Brakeman, `bundler-audit` and `importmap audit`. CI builds both
images.

The full changelog is in [CHANGELOG.md](https://github.com/Elevate08/familyplates/blob/master/CHANGELOG.md#v140---2026-10-15).
