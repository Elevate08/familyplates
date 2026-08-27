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
| **Reset Member PINs & Change Master Email** | ✅ | ❌ |

---

## 🎨 User Preferences Portal (`/preferences`)

Every logged-in member can personalize their kitchen experience by clicking their avatar pill in the top-right and selecting **"My Preferences"**:

* **Name:** Update display name in the planner and cook rosters.
* **Avatar Icons:** 8 custom kitchen-themed SVG icons:
  * 👨‍🍳 `chef-hat`
  * ✨ `sparkles`
  * 🍕 `pizza`
  * 🍔 `burger`
  * 🥑 `avocado`
  * 🧁 `cupcake`
  * ☕ `coffee`
  * 🥗 `salad`
* **Color Palettes:** 12 vibrant kitchen accent colors (Ocean Blue, Berry Pink, Sunset Amber, Emerald Green, Royal Violet, Coral Orange, Indigo, Crimson, Teal, Lemon, Sky, Forest).
* **PIN Change:** Admins can change their 4-digit security PIN anytime.

---

## ⚙️ Admin Control Center (`/admin`)

The Admin Control Center is restricted to Admin members and requires entering the 4-digit PIN upon switching to an admin profile:

1. **Family Roster Management (`/admin/family_members`):**
   * Add new family members.
   * Toggle Admin/Member role.
   * Reset forgotten 4-digit PINs.
2. **Master Account Credentials (`/admin/account`):**
   * Modify the primary family email address and password.
3. **Household & Calendar Settings (`/admin/household/edit`):**
   * Household display name.
   * Default breakfast, lunch, and dinner start hours.
   * Google Calendar Service Account credentials & Real-Time Sync.
