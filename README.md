# 🍽️ FamilyPlates

**Family meal planning, curated recipes, 1-page fridge calendar printouts, and universal calendar subscriptions.**

FamilyPlates is a streamlined, self-hosted web application built for modern families. It eliminates the daily *"What's for dinner?"* chaos by combining collaborative weekly meal planning, automatic grocery list generation, ink-friendly refrigerator printouts, and universal calendar subscriptions (.ics / webcal) for Apple Calendar, Google Calendar, Outlook, and mobile devices.

---

## ✨ Features

* **🗓️ Interactive Weekly & Monthly Meal Planner:** Schedule breakfast, lunch, and dinner with 1-click recipe assignment, cook assignments, and notes.
* **📅 Universal Calendar Subscriptions:** Live `.ics` / `webcal` feeds that sync planned meals to Apple Calendar, Google Calendar, Outlook, and mobile devices with 1-tap setup and per-cook shift filtering.
* **🖨️ 1-Page Refrigerator Printouts:** Clean, high-contrast weekly and monthly letter-landscape printouts designed for standard fridge hanging.
* **🛒 Aisle-Organized Grocery Checklist:** Aggregates ingredients across planned meals, categorized by supermarket aisle with a mobile-friendly strike-off interface.
* **🛡️ Smart Pantry Shield:** Flag staple items in your kitchen pantry so they are automatically excluded or highlighted on your shopping list.
* **🌐 1-Click Recipe Web Scraper:** Import recipes from any website using JSON-LD metadata.
* **👥 Family Profiles & Personalization:** Custom avatars, 12 kitchen accent color palettes, and quick profile switcher.
* **🔐 Admin Control Center & PIN Security:** 4-digit security PIN enforcement for Admin/Organizer profiles, roster management, and master account settings.

---

## 📚 Documentation & Wiki

Explore the full documentation and guides in the [`docs/`](./docs/README.md) directory:

| Guide | Link |
| :--- | :--- |
| **Universal Calendar Subscriptions Guide** | [Read Guide](./docs/universal-calendar-subscriptions.md) |
| **Getting Started & Local Setup** | [Read Guide](./docs/getting-started.md) |
| **Admin & User Preferences** | [Read Guide](./docs/admin-and-user-preferences.md) |
| **Weekly & Monthly Meal Planning** | [Read Guide](./docs/weekly-meal-planning.md) |
| **Recipes & Pantry Management** | [Read Guide](./docs/recipes-and-pantry.md) |
| **System Architecture & Tech Stack** | [Read Guide](./docs/architecture.md) |

---

## 🚀 Quick Start (Docker Compose)

The easiest way to run FamilyPlates is with **Docker Compose**:

```yaml
services:
  familyplates:
    image: ghcr.io/elevate08/familyplates:latest
    container_name: familyplates
    restart: unless-stopped
    ports:
      - "3000:80"
    environment:
      - RAILS_ENV=production
      - "SECRET_KEY_BASE=${SECRET_KEY_BASE:?required - generate one with openssl rand -hex 64}"
      - RAILS_SERVE_STATIC_FILES=true
      - RAILS_LOG_TO_STDOUT=true
    volumes:
      - familyplates_data:/rails/storage

volumes:
  familyplates_data:
```

```bash
# Start the container
docker compose up -d
```

Visit [`http://localhost:3000`](http://localhost:3000) in your browser to launch the initial 4-step onboarding wizard.

A home server does not need a public hostname or a mail server. Hosted mode will not start until `APP_HOST` and `SMTP_ADDRESS` are set. The [deployment guide](./docs/getting-started.md) lists both.

---

## 💻 Bare-Metal Development

For local development and contributing:

```bash
# Clone the repository
git clone https://github.com/Elevate08/familyplates.git
cd familyplates

# Install gems
bundle install

# Setup database & migrations
bin/rails db:setup

# Start development server (Puma + Tailwind CSS watcher)
bin/dev
```

---

## 🧪 Testing

```bash
bin/rails test              # unit and integration tests, including the authorization matrix
bin/rails test:system       # Selenium browser tests
bin/e2e                     # Playwright: flows, screenshots, and a crawl of every page
bin/coverage-criteria       # Fizzy acceptance criteria with no test tagged to them
bin/ci                      # everything CI runs, in order
```

**Playwright needs Docker.** `bin/e2e` runs the browser in the official Playwright
image at the version in `package-lock.json`, the same image CI uses, so screenshots
render identically on every machine. Arguments pass through to `playwright test`
(`bin/e2e e2e/flows --project=desktop-light`). Without Docker,
`E2E_BROWSER=local bin/e2e` uses a local Chromium (`PLAYWRIGHT_CHROMIUM_PATH=/usr/bin/chromium`
for a system one): flows are checked, but screenshot diffs there are not meaningful.

**Four workers by default** (`E2E_WORKERS=2 bin/e2e` for fewer). Each worker has its own
Rails server on port 3100 + N and its own `storage/e2e-N.sqlite3`, because a test resets the
database and sets the server's mode and clock. Playwright hands out whole spec files, so a
long spec keeps one worker busy: the route crawl is one file per role in `e2e/crawl/` for
that reason.

**Screenshot baselines** live in `e2e/snapshots/` and are only ever recorded with
`bin/e2e-update-snapshots`, which uses the same container. On Omarchy, where users are not in the
`docker` group by default, both scripts ask for your sudo password once at the start and elevate only
the `docker` commands. Review the PNGs before
committing them: an update accepts whatever the page looks like now.

**Adding a route.** Two tests read `config/routes.rb` and fail until a new route is
accounted for:

* `test/integration/authorization_matrix_test.rb` needs a row saying who may use it
  (guest, member, organizer, platform operator) and, if it takes a record id, what
  another household's id gets.
* The Playwright route crawl visits every GET route as each of those visitors and
  checks it for server errors, console errors, broken requests, axe (WCAG 2.1 AA)
  violations and sideways scroll on a phone. A GET route with parameters needs an
  entry in `e2e/support/route-catalogue.ts`, either the record to visit it with or
  the reason it is skipped.

**Acceptance criteria.** `test/acceptance_criteria.yml` lists each Fizzy card's
criteria. Tag the test that proves one with `# @card-49.1` above a Minitest test,
or `@card-49.1` in a Playwright title or `tag`.

**Stripe.** Tests use a Stripe sandbox or nothing. The real-checkout test runs only
with `ENABLE_REAL_STRIPE_TESTS=true` and a `sk_test_`/`rk_test_` key, and both the
Playwright config and the Rails test environment refuse to start with a live key.

---

## 📄 License
This project is open-source under the [MIT License](LICENSE).
