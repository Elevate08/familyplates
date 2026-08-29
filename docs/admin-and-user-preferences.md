# 🛡️ Admin Control Center & User Preferences

FamilyPlates is designed around a single family household with a shared primary login, individual profile switchers, customizable themes, and robust Admin security.

---

## 👥 Profile Roles & Permissions

FamilyPlates supports two types of household members:

| Feature | Organizer (Admin) | Family Member |
| :--- | :---: | :---: |
| Plan & Schedule Meals | ✅ | ✅ |
| Submit Recipe Cravings | ✅ | ✅ |
| View & Check off Grocery List | ✅ | ✅ |
| Customize Name, Avatar Icon & Accent Color | ✅ | ✅ |
| **4-Digit Security PIN Requirement** | **Mandatory** | ❌ (1-Tap Switch) |
| **Access Admin Control Center (`/admin`)** | ✅ | ❌ |
| **Edit Household Name & Meal Times** | ✅ | ❌ |
| **Manage Google Calendar Sync & Credentials** | ✅ | ❌ |
| **Reset Member PINs & Manage Roster** | ✅ | ❌ |

---

## 🎨 User Preferences Portal (`/preferences`)

Every logged-in member can personalize their kitchen experience by clicking their avatar pill in the top-right and selecting **"My Preferences"**:

* **Name:** Update display name in the planner and cook rosters.
* **Avatar Icons:** Custom kitchen-themed SVG icons (`chef-hat`, `utensils`, `heart`, `star`, `smile`, `flame`, `sparkles`, `award`).
* **Color Palettes:** 12 vibrant kitchen accent colors.
* **PIN Change:** Admins can change their 4-digit security PIN anytime.

---

## ⚙️ Admin Control Center (`/admin`)

The Admin Control Center is restricted to Admin members and requires entering the 4-digit PIN upon switching to an admin profile:

1. **Family Roster Management (`/admin/family_members`):**
   * Add new family members.
   * Toggle Admin/Member role.
   * Reset forgotten 4-digit PINs.
2. **Household & Calendar Settings (`/admin/household/edit`):**
   * Household display name.
   * Default breakfast, lunch, and dinner start hours.
   * Google Calendar Service Account credentials & Real-Time Sync.
