# Task List: Single-Family Kitchen Appliance, Admin Panel & User Preferences

## Phase 1: Foundation & Model Rules

### Task 1: Single-Family Lockdown & Model PIN Rules
**Description:** Lock public registration once a household exists, and update the `FamilyMember` model so only admins can have or set a PIN.
**Acceptance criteria:**
- [x] `RegistrationsController#new` and `#create` redirect with an alert if a `Household` already exists.
- [x] `FamilyMember` clears/rejects `pin` if `role != "admin"`.
- [x] `FamilyMember#requires_pin?` returns true only for admins with a PIN present.
- [x] Tests for single-family registration lock and PIN validation pass.
**Dependencies:** None
**Files:**
- `app/controllers/registrations_controller.rb`
- `app/models/family_member.rb`
- `test/models/family_member_test.rb`
- `test/controllers/registrations_controller_test.rb`

---

## Phase 2: User Preferences

### Task 2: Self-Service User Preferences Portal (`/preferences`)
**Description:** Create a user preferences page where any logged-in family member can update their display name, avatar icon, theme accent color, and (if admin) their 4-digit PIN.
**Acceptance criteria:**
- [x] `GET /preferences` renders the edit preferences view for `Current.family_member`.
- [x] `PATCH /preferences` updates name, avatar icon, and avatar color (and PIN for admins).
- [x] Non-admin members cannot submit a PIN change.
- [x] Interactive UI with 8 visual avatar icons and 12-color swatch palette.
- [x] "My Preferences" link present in navbar dropdown.
- [x] Tests for `PreferencesController` pass.
**Dependencies:** Task 1
**Files:**
- `config/routes.rb`
- `app/controllers/preferences_controller.rb`
- `app/views/preferences/edit.html.erb`
- `app/views/shared/_navbar.html.erb`
- `test/controllers/preferences_controller_test.rb`

---

## Phase 3: Admin Control Center

### Task 3: Admin Control Center (`/admin`)
**Description:** Build the Admin Control Center for household administrators to manage the member roster, reset admin PINs, modify primary account credentials, and configure household settings.
**Acceptance criteria:**
- [x] `Admin::BaseController` restricts access exclusively to members with `role: "admin"`.
- [x] `Admin::DashboardController` provides an overview of household stats, roster, and quick admin actions.
- [x] `Admin::FamilyMembersController` supports adding, editing, removing members, and 1-click resetting/clearing admin PINs.
- [x] `Admin::AccountsController` allows admins to update the master `User` email address and password.
- [x] `Admin::HouseholdsController` allows updating household name and regenerating calendar feed token.
- [x] "Admin Control Center" link shown in navbar dropdown only for admin members.
- [x] Controller and integration tests for all admin modules pass.
**Dependencies:** Task 1, Task 2
**Files:**
- `config/routes.rb`
- `app/controllers/admin/base_controller.rb`
- `app/controllers/admin/dashboard_controller.rb`
- `app/controllers/admin/family_members_controller.rb`
- `app/controllers/admin/accounts_controller.rb`
- `app/controllers/admin/households_controller.rb`
- `app/views/admin/dashboard/index.html.erb`
- `app/views/admin/family_members/index.html.erb`
- `app/views/admin/family_members/edit.html.erb`
- `app/views/admin/accounts/edit.html.erb`
- `app/views/admin/households/edit.html.erb`
- `app/views/shared/_navbar.html.erb`
- `test/controllers/admin/` tests

---

## Phase 4: Integration & Polish

### Task 4: Profile Switcher & Views Harmonization
**Description:** Harmonize the profile switcher, profile selector, and layout styling so non-admins never encounter PIN prompts and accent themes reflect smoothly.
**Acceptance criteria:**
- [x] `ProfilesController#set` and `FamilyMembersController#switch` only require PIN if `member.requires_pin?`.
- [x] Profile select view displays PIN lock badge only on admin profiles with PINs.
- [x] Full test suite passes without errors or regressions.
**Dependencies:** Tasks 1-3
**Files:**
- `app/views/profiles/select.html.erb`
- `app/views/family_members/_switcher.html.erb`
- `test/controllers/profiles_controller_test.rb`
