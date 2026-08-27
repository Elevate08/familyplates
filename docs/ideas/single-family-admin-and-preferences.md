# Single-Family Kitchen Appliance, Admin Control Center & User Preferences

## Problem Statement
How might we transform FamilyPlates into a dedicated single-family kitchen appliance with an empowered Admin Control Center for parents (PIN resets, roster management, primary account email management, kitchen settings) and a self-service personalization portal for family members (icon, color, name)?

## Recommended Direction
Transition the architecture to a dedicated single-household instance model. Public registration is locked once the household is established.

1. **Admin Control Center (`/admin`):**
   - Protected by `role: "admin"` and PIN verification.
   - **Member Roster Management:** Add, edit, or remove family members and assign roles (`admin` vs `member`).
   - **Admin PIN Control:** Set, change, or reset 4-digit PINs for Admin profiles (non-admin members do not have or use PINs).
   - **Master Account Settings:** Modify the primary login email address and master password directly from the admin panel.
   - **Household Settings:** Edit household name and view/regenerate the calendar `.ics` feed token.

2. **Self-Service User Preferences (`/preferences`):**
   - Accessible to the currently active family member from the navbar user dropdown.
   - Custom display name.
   - Custom avatar icon (interactive selector with 8+ kitchen icons: chef hat, utensils, heart, star, smile, flame, sparkles, award).
   - Custom theme accent color (12-color palette swatch with real-time accent tint preview).
   - PIN management: Displayed only for Admin profiles; non-admin members do not need or configure PINs.

3. **Single-Family Registration Lockdown:**
   - Initial onboarding / first-run setup creates the single household and primary admin user.
   - Subsequent visits to `/registration` redirect to login/root, locking down the instance from rogue household creation.

## Key Assumptions to Validate
- [ ] Single-household lock: Ensure all planner, recipe, grocery, and pantry queries operate reliably on the single household instance without multi-tenant registration leaks.
- [ ] Admin Recovery: Verify that an authenticated admin can always update master credentials and reset any admin PIN without requiring legacy recovery steps.
- [ ] Theme Reactivity: Ensure changing avatar color and icon in `/preferences` immediately re-tints the app's CSS custom property (`--user-accent`) and updates all active headers and navigation badges.

## MVP Scope

### In Scope:
- **Registration Lock:** Prevent new household registrations if a household record already exists.
- **Admin Control Center (`/admin`):**
  - Admin dashboard layout and navigation (`Admin::BaseController` with `before_action :require_admin`).
  - Family member roster with role badges (`Admin` vs `Member`) and PIN indicators.
  - 1-Click PIN Reset / Update for Admin members.
  - Master Account management: Edit primary login email address and password.
  - Household settings (Family Name, Calendar token regeneration).
- **User Preferences Portal (`/preferences`):**
  - Dedicated preferences controller & view (`PreferencesController#edit`, `#update`).
  - Personalization fields: Name, Avatar Icon (visual icon selector), Theme Color (12-palette swatch selector).
  - Conditional PIN update section visible only when `current_family_member.admin?`.
- **Navigation & Role Guards:**
  - Updated navbar dropdown: "My Preferences", "Admin Control Center" (only for admins), "Switch Cook Profile", "Sign Out".
  - PIN modal trigger on profile switcher restricted to Admin profiles only.

## Not Doing (and Why)
- **PINs for non-admin members** — Kids and regular family members should enjoy frictionless 1-tap switching on kitchen iPads without entering PINs.
- **Separate email/password logins for every family member** — Unnecessary login friction for kids and family members on shared kitchen devices.
- **Multi-household tenant switching** — Intentionally removed. The app serves one dedicated family.
- **Complex RBAC matrices** — Roles remain strictly binary: `admin` (accesses Admin Center, manages accounts & PINs) and `member` (plans meals, requests recipes, customizes own icon/color/name).
- **Biometric / OAuth 3rd-party auth** — Unnecessary complexity for a single household kitchen appliance.

## Open Questions
- None. Ready for implementation planning.
