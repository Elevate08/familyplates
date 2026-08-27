# Google Calendar Service Account Sync

## Problem Statement
How might we automatically create, update, and manage meal events inside a family's existing Google Calendar in real time using a frictionless Google Service Account integration?

## Recommended Direction
Use a Google Cloud Service Account integration with Google Calendar API. Families share their existing Google Calendar (Primary or Shared Family Calendar) with a dedicated Service Account email (e.g. `familyplates-sync@...`) with "Make changes to events" permissions.

FamilyPlates communicates directly with the Google Calendar API v3 to insert, update, and delete events in real time when meals are scheduled, updated, or cleared in the weekly planner.

### Advantages
- **Zero Token Expiration:** No OAuth refresh tokens that expire or disconnect.
- **No Unverified App Warnings:** Avoids Google OAuth consent screen verification requirements.
- **Shared Calendar Support:** Works directly with family shared calendars.
- **Instant Real-Time Sync:** Events appear within seconds on all family phones and smart displays.

## Event Structure & Scheduling
- **Times:** Configured per household (Default: Breakfast 8:00 AM, Lunch 12:30 PM, Dinner 6:00 PM; duration 45m-60m).
- **Summary (Title):** `🍽️ Dinner: [Recipe / Custom Title] (Cook: [Name])`
- **Description:**
  - 👨‍🍳 Cook: [Family Member Name]
  - ⏱️ Prep: [X]m | Cook: [Y]m | Servings: [N]
  - 📋 Ingredients snippet
  - 🔗 Direct URL link back to recipe in FamilyPlates

## MVP Scope
1. **Household Database Schema:**
   - `google_calendar_id` (string)
   - `google_calendar_enabled` (boolean, default: false)
   - `breakfast_time` (string, default: "08:00")
   - `lunch_time` (string, default: "12:30")
   - `dinner_time` (string, default: "18:00")
   - `meal_plan_slots.google_event_id` (string)
2. **Admin Configuration UI (`/admin/households/edit`):**
   - Service account email display with copy button
   - Google Calendar ID input
   - Toggle switch to enable/disable sync
   - Test Connection & Sync action
   - Configurable meal times
3. **Google Calendar API Service (`GoogleCalendarService`):**
   - Service account authentication (JWT / Google API client)
   - `create_or_update_event(slot)`
   - `delete_event(slot)`
   - `test_connection(calendar_id)`
4. **Background Jobs (`SyncMealPlanSlotJob`, `SyncMealPlanWeekJob`):**
   - Dispatched asynchronously on slot change or manual week sync
   - Graceful error handling and retry

## Key Assumptions to Validate
- [ ] Service Account has permissions on the target Google Calendar.
- [ ] Meal times default to household standards unless overridden.
- [ ] Background job prevents latency during meal planner interaction.

## Not Doing (and Why)
- **Two-way sync (GCal -> FamilyPlates):** Not listening to Google Calendar webhooks to alter FamilyPlates plans. *Why: Adds complex conflict resolution for minimal user benefit.*
- **Per-user OAuth logins:** Not requiring each family member to log in with Google. *Why: FamilyPlates is a single household app syncing to one shared family calendar.*
