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

## 🔐 Initial Setup & First Login

1. On first run, create your household and primary account credentials on the registration page (`/registration/new`).
2. Add your family members (Organizers/Parents and regular members).
3. Set 4-digit PINs for Organizers to protect Admin access and sensitive settings.
4. Follow the [Google Calendar Guide](./google-calendar-integration.md) to enable automatic meal synchronization.
