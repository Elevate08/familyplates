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

Run the automated test suite:

```bash
bundle exec rails test
```

---

## 📄 License
This project is open-source under the [MIT License](LICENSE).
