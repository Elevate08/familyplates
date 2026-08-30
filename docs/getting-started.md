# 🚀 Getting Started with FamilyPlates

This guide walks you through setting up and running FamilyPlates locally or in production.

---

## 📋 Prerequisites

* **Ruby:** `4.0.x` or `3.4.x` (managed via `mise`, `asdf`, `rbenv`, or system)
* **SQLite:** `3.40+`
* **Node / Propshaft Assets:** Built with modern ESM import maps and Tailwind CSS v4.

---

## ⚙️ Quick Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-username/familyplates.git
   cd familyplates
   ```

2. **Install Ruby gems:**
   ```bash
   bundle install
   ```

3. **Set up the Database & Seed Data:**
   ```bash
   bin/rails db:setup
   ```

4. **Start the Development Server:**
   ```bash
   bin/dev
   ```
   * Or run standard Puma + Tailwind watcher:
     ```bash
     bin/rails server
     ```

5. **Open in Browser:**
   Visit [`http://localhost:3000`](http://localhost:3000).

---

## 🧪 Running Tests

FamilyPlates comes with comprehensive unit, integration, and service tests:

```bash
bundle exec rails test
```

---

## 🔐 Initial Setup & First Boot

1. On first run, FamilyPlates presents a 4-step **Onboarding Wizard** (`/onboarding`):
   * Create your Family Household name.
   * Add family members & assign Organizer (Admin) roles with optional 4-digit PINs.
   * Pick starter recipes for your Recipe Box.
   * Confirm On-Hand pantry items to activate the **Pantry Shield**.
2. Follow the [Google Calendar Guide](google-calendar-integration) to enable automatic meal synchronization.
