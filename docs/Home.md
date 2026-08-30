# 📖 Welcome to the FamilyPlates Wiki

**FamilyPlates** is a self-hosted family meal planning, recipe curation, fridge calendar printing, and real-time Google Calendar synchronization application built with Ruby on Rails 8 and Tailwind CSS.

---

## 🗂️ Documentation Navigation

| Guide | Summary |
| :--- | :--- |
| **[🚀 Getting Started](getting-started)** | Initial setup, environment requirements, database setup, and local run guide. |
| **[📅 Google Calendar Sync Guide](google-calendar-integration)** | Step-by-step setup for real-time meal sync via Google Cloud Service Accounts. |
| **[🛡️ Admin & User Preferences](admin-and-user-preferences)** | Profile-only auth, Organizer PIN security, member customization (colors & icons). |
| **[🗓️ Weekly & Monthly Meal Planning](weekly-meal-planning)** | Interactive meal scheduler, cook assignments, cravings, and 1-page fridge printouts. |
| **[🍳 Recipes & Pantry Management](recipes-and-pantry)** | Recipe scraper, structured ingredients, weighted aisle learning, and Pantry Shield. |
| **[🏗️ System Architecture](architecture)** | Technical stack, data models, Solid Queue workers, and security model. |

---

## 🌟 Core Architecture & Features

```mermaid
graph TD
    A[Family Household] --> B[Roster: Organizers & Family Members]
    B --> C[Recipe Box & Web Importer]
    B --> D[Weekly / Monthly Meal Planner]
    C --> D
    D --> E[1-Page Fridge Sheet Printout]
    D --> F[Aisle-Organized Grocery List]
    D --> G[Real-Time Google Calendar Sync]
    B --> H[User Preferences: Icons & Colors]
    B --> I[Admin Control Center: PINs & Settings]
```

* **Zero-Password Profile Auth:** Direct 1-tap switching between family cook profiles with Organizer PIN protection.
* **Instant Google Calendar Sync:** Direct write sync to shared family Google Calendars via Service Account with zero OAuth popup friction or token expiration.
* **Printable Fridge Calendars:** Optimized landscape 1-page weekly & monthly refrigerator prints with auto-print support.
* **Smart Grocery Checklist:** Aisle-sorted ingredient aggregation with automatic Pantry Shield on-hand deduplication.
