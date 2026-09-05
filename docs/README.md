# 📖 FamilyPlates Wiki & Documentation

Welcome to the **FamilyPlates** documentation repository. FamilyPlates is a self-hosted family meal planning, recipe curation, fridge calendar printing, and universal calendar subscription application.

---

## 🗂️ Documentation Index

| Guide | Description |
| :--- | :--- |
| [🚀 Getting Started](./getting-started.md) | Initial setup, environment requirements, database setup, and local run guide. |
| [📅 Universal Calendar Subscriptions](./universal-calendar-subscriptions.md) | Live `.ics` / `webcal` calendar feeds for Apple Calendar, Google Calendar, and Outlook. |
| [🛡️ Admin & User Preferences](./admin-and-user-preferences.md) | Admin Control Center, 4-digit PIN security, member customization (colors & icons). |
| [🗓️ Weekly & Monthly Meal Planning](./weekly-meal-planning.md) | Interactive weekly/monthly planner, cook assignments, cravings, and fridge printouts. |
| [🍳 Recipes & Pantry Management](./recipes-and-pantry.md) | Recipe scraper, ingredient aisle categorization, and the Pantry Shield grocery list. |
| [🏗️ System Architecture](./architecture.md) | Technical stack, data models, Solid Queue workers, and security model. |

---

## 🌟 Core System Highlights

```mermaid
graph TD
    A[Primary User / Household] --> B[Roster: Organizers & Family Members]
    B --> C[Recipe Collection & URL Importer]
    B --> D[Weekly / Monthly Meal Planner]
    C --> D
    D --> E[1-Page Fridge Sheet Printout]
    D --> F[Aisle-Organized Grocery List]
    D --> G[Universal Calendar Subscriptions (.ics)]
    B --> H[User Preferences: Icons & Colors]
    B --> I[Admin Control Center: PINs & Settings]
```

* **Single Household Focus:** Tailored for a single family with multiple shared cook profiles.
* **Universal Calendar Subscriptions:** Zero-configuration live `.ics` feeds with 1-tap Apple Calendar and Google Calendar subscription buttons, cook filtering, and token rotation.
* **Printable Fridge Calendars:** Optimized landscape 1-page weekly & monthly refrigerator prints.
* **Smart Grocery Checklist:** Aisle-sorted ingredient aggregation with automatic Pantry Shield staple deduplication.
