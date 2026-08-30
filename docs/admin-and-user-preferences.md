# 🛡️ Admin Control Center & User Preferences

FamilyPlates is designed around a seamless household profile model — eliminating master email/passwords in favor of 1-tap family cook profile switching, customizable avatar styles, and secure 4-digit PIN protection for Organizer accounts.

---

## 👥 Profile Roles & Permissions

FamilyPlates supports two types of household members:

| Feature | Organizer (Admin) | Family Member |
| :--- | :---: | :---: |
| Plan & Schedule Meals | ✅ | ✅ |
| Submit Recipe Requests & Cravings | ✅ | ✅ |
| View & Check off Grocery List | ✅ | ✅ |
| Add & Edit Recipes | ✅ | ✅ |
| Customize Name, Avatar Icon & Accent Color | ✅ | ✅ |
| **4-Digit Security PIN Requirement** | **Protected** | ❌ (1-Tap Switch) |
| **Access Admin Control Center (`/admin`)** | ✅ | ❌ |
| **Edit Household Name & Default Meal Times** | ✅ | ❌ |
| **Manage Google Calendar Sync & Credentials** | ✅ | ❌ |
| **Manage Household Roster & Member Roles** | ✅ | ❌ |

---

## 🔐 Profile-Only Authentication & Profile Switcher

* **No Master Password Friction:** Access the app directly through the visual family profile switcher (`/select_profile`).
* **1-Tap Switching for Kids & Members:** Non-admin family members can tap their avatar to immediately plan meals or check groceries.
* **Organizer PIN Protection:** Switching to an Organizer (Admin) profile requires a quick 4-digit PIN entry modal to prevent unauthorized access to household administration.
* **Header Profile Switcher:** Switch active cooks on the fly with the top-right profile pill menu.

---

## 🎨 User Preferences Portal (`/preferences`)

Every member can personalize their experience:

* **Display Name:** Change display name shown in the planner, cook tags, and fridge sheet.
* **Avatar Icons:** Custom kitchen-themed SVG icons (`chef-hat`, `utensils`, `heart`, `star`, `smile`, `flame`, `sparkles`, `award`).
* **Color Palettes:** 12 vibrant kitchen accent colors.
* **PIN Management:** Organizers can update their 4-digit PIN anytime.

---

## ⚙️ Admin Control Center (`/admin`)

The Admin Control Center is restricted to Organizers:

1. **Family Roster Management (`/admin/family_members`):**
   * Add new family members or kids.
   * Promote members to Organizer or demote to standard member.
   * Reset forgotten 4-digit Organizer PINs.
2. **Household & Meal Schedule (`/admin/household/edit`):**
   * Kitchen / Household display name.
   * Default breakfast, lunch, and dinner start times (used when creating calendar events).
3. **Google Calendar Direct Sync (`/admin/calendar/edit`):**
   * Service account credentials management, live connection tester, and manual 1-click week sync.
