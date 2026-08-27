# 🍽️ FamilyPlates

**Family meal planning, curated recipes, 1-page fridge calendar printouts, and real-time Google Calendar sync.**

FamilyPlates is a streamlined, self-hosted web application built for modern families. It eliminates the daily *"What's for dinner?"* chaos by combining collaborative weekly meal planning, automatic grocery list generation, ink-friendly refrigerator printouts, and direct background synchronization to your shared Google Calendar.

---

## ✨ Features

* **🗓️ Interactive Weekly & Monthly Meal Planner:** Schedule breakfast, lunch, and dinner with 1-click recipe assignment, cook assignments, and notes.
* **📅 Direct Google Calendar Real-Time Sync:** Automatically writes scheduled meals, cooks, prep times, and ingredients to your shared family Google Calendar via Google Service Account.
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
| **Google Calendar Integration Guide** | [Read Guide](./docs/google-calendar-integration.md) |
| **Getting Started & Local Setup** | [Read Guide](./docs/getting-started.md) |
| **Admin & User Preferences** | [Read Guide](./docs/admin-and-user-preferences.md) |
| **Weekly & Monthly Meal Planning** | [Read Guide](./docs/weekly-meal-planning.md) |
| **Recipes & Pantry Management** | [Read Guide](./docs/recipes-and-pantry.md) |
| **System Architecture & Tech Stack** | [Read Guide](./docs/architecture.md) |

---

## 🚀 Quick Start

### 1. Prerequisites
* Ruby `4.0` or `3.4`
* SQLite `3.40+`

### 2. Setup
```bash
# Clone the repository
git clone https://github.com/your-username/familyplates.git
cd familyplates

# Install gems
bundle install

# Setup database & migrations
bin/rails db:setup

# Start development server
bin/dev
```

Visit [`http://localhost:3000`](http://localhost:3000) in your browser.

---

## 🧪 Testing

Run the automated test suite:

```bash
bundle exec rails test
```

---

## 📄 License
This project is open-source under the [MIT License](LICENSE).
