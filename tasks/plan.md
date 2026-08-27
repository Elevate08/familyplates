# Implementation Plan: Single-Family Architecture, Admin Panel & User Preferences

## Overview
Transform FamilyPlates into a dedicated single-family kitchen appliance. This involves locking public registration once the primary household is configured, establishing a full-featured Admin Control Center (`/admin`) for parents/organizers (member management, PIN resets, primary account email/password updates, calendar feed configuration), and providing a self-service User Preferences portal (`/preferences`) for all family members to customize their name, avatar icon, and theme color.

---

## Architectural Decisions
1. **Single-Family Instance Lock:** Public registration (`/registration`) is locked once the household exists. Attempted registrations redirect to login or root with an informative message.
2. **Role & PIN Policy:** 
   - Non-admin members (`role: "member"`) have zero PIN friction (1-tap switching) and cannot set PINs.
   - Admin members (`role: "admin"`) can optionally set a 4-digit PIN to secure their organizer privileges.
   - Admins can reset, change, or clear any admin's PIN from `/admin`.
3. **Master Account Management:** The primary `User` credentials (email address & password) are editable by admins via `/admin/account`.
4. **User Preferences Portal:** Active family members access `/preferences` to configure display name, avatar icon (8 options), and theme accent color (12 options). Admins can also update their own PIN here.
5. **Admin Access Control:** All `/admin` endpoints inherit from `Admin::BaseController`, enforcing `current_family_member&.admin?`.

---

## Dependency Graph
```
Single-Family Registration Lock & Model PIN Rules (Task 1)
                  │
                  ├── User Preferences Portal (/preferences) (Task 2)
                  │
                  └── Admin Control Center (/admin) (Task 3)
                            │
                            └── Profile Switcher & Views Harmonization (Task 4)
```

---

## Task List

### Phase 1: Foundation & Model Rules
- [ ] **Task 1: Single-Family Lockdown & Model PIN Rules**
  - Lock `RegistrationsController` when a household already exists.
  - Enforce in `FamilyMember` that only admin members can have a PIN.
  - Add unit tests for registration lockdown and PIN validation.

### Phase 2: User Preferences
- [ ] **Task 2: Self-Service User Preferences Portal**
  - Implement `PreferencesController` (`edit`, `update`).
  - Build `app/views/preferences/edit.html.erb` with interactive icon picker (8 SVG icons), color swatch selector (12 palette colors), name input, and conditional PIN field for admins.
  - Add "My Preferences" link to navbar dropdown.
  - Add controller and integration tests for preferences.

### Phase 3: Admin Control Center
- [ ] **Task 3: Admin Control Center (`/admin`)**
  - Create `Admin::BaseController` with `require_admin` filter.
  - Build `Admin::DashboardController` (system & kitchen overview).
  - Build `Admin::FamilyMembersController` (member roster, add/edit/destroy members, 1-click PIN reset/clear).
  - Build `Admin::AccountsController` (update primary login email address & password).
  - Build `Admin::HouseholdsController` (rename household, regenerate calendar token).
  - Add "Admin Control Center" link to navbar for admin members.
  - Add admin controller & security tests.

### Phase 4: Integration & Polish
- [ ] **Task 4: Profile Switcher & Navigation Harmonization**
  - Update `ProfilesController` and views so non-admins never trigger PIN modal.
  - Verify theme color reactivity across layout.
  - Run full test suite and verify end-to-end user flows.

---

## Risks and Mitigations
| Risk | Impact | Mitigation |
| :--- | :--- | :--- |
| **Admin locks themselves out of PIN** | High | Admins logged in via the master user session can reset PINs via the Admin Control Center without needing the old PIN. |
| **Non-admin accesses /admin directly** | High | `Admin::BaseController` strictly enforces `current_family_member&.admin?` before all actions and redirects unauthorized users. |
| **Existing test regressions** | Medium | Run `rails test` after each phase to verify all 80+ existing tests continue to pass. |
