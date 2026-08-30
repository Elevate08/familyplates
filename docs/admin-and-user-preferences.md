# 🛡️ Admin Control Center & User Preferences

FamilyPlates is designed around a seamless household profile model — eliminating master email/passwords in favor of 1-tap family cook profile switching, customizable avatar styles, and secure 4-digit PIN protection for Organizer accounts.

---

## 👥 Profile Roles & Permissions Matrix

FamilyPlates provides distinct permission levels tailored for family organizers and kids/household members:

| Capability / Action | Organizer (Admin) | Family Member |
| :--- | :---: | :---: |
| **Weekly & Monthly Meal Scheduling** (Add, edit, reschedule, delete meal slots) | ✅ | ❌ *(Read-Only Planner)* |
| **Recipe Management** (Create, edit, or delete recipes) | ✅ | ❌ *(Browse & View Only)* |
| **1-Click Recipe Web Importer** (Import recipes from URL) | ✅ | ❌ |
| **Recipe Cravings & Requests** (Submit meal requests for upcoming weeks) | ✅ | ✅ |
| **Smart Grocery Checklist** (Mark items as purchased, reset list) | ✅ | ❌ *(View & Copy Plain Text Only)* |
| **Fridge Schedule Printing** (1-page weekly & monthly fridge prints) | ✅ | ✅ |
| **Personal Preferences** (Customize name, avatar icon, and accent color) | ✅ | ✅ |
| **4-Digit PIN Protection** | **Mandatory** | ❌ *(1-Tap Instant Switch)* |
| **Access Admin Control Center (`/admin`)** | ✅ | ❌ |
| **Household Roster Management** (Add members, change roles, reset PINs) | ✅ | ❌ |
| **Household Branding & Meal Schedule** (Household name, meal start times) | ✅ | ❌ |
| **Google Calendar Real-Time Sync** (Service account keys, sync triggers) | ✅ | ❌ |

---

## 🔐 Profile-Only Authentication & Profile Switcher

* **No Master Password Friction:** Access the app directly through the visual family profile switcher (`/select_profile`).
* **1-Tap Switching for Kids & Members:** Non-admin family members can tap their avatar to immediately browse recipes, view the scheduled planner, or check groceries.
* **Organizer PIN Protection:** Switching to an Organizer (Admin) profile triggers a 4-digit PIN modal to protect meal scheduling, recipe editing, and household administration.
* **Header Profile Switcher:** Switch active cooks quickly at any time from the top-right profile pill.

---

## 🎨 User Preferences Portal (`/preferences`)

Every member can personalize their kitchen experience:

* **Display Name:** Customize your display name shown in the planner, cook tags, and fridge sheet.
* **Avatar Icons:** Custom kitchen-themed SVG icons (`chef-hat`, `utensils`, `heart`, `star`, `smile`, `flame`, `sparkles`, `award`).
* **Color Palettes:** 12 vibrant kitchen accent colors.
* **PIN Management:** Organizers can update their 4-digit security PIN anytime.

---

## ⚙️ Admin Control Center (`/admin`)

The Admin Control Center is restricted to Organizers with PIN verification:

1. **Family Roster Management (`/admin/family_members`):**
   * Add new family members or kids.
   * Promote members to Organizer or demote to standard member.
   * Reset forgotten 4-digit Organizer PINs.
2. **Household & Meal Schedule (`/admin/household/edit`):**
   * Household / Family Kitchen display name.
   * Default breakfast, lunch, and dinner start times (used when creating calendar events).
3. **Google Calendar Direct Sync (`/admin/calendar/edit`):**
   * Service account credentials management, live connection tester, and manual 1-click week sync.
