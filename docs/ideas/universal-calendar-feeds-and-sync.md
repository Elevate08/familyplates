# Universal Calendar Subscriptions & 1-Click Sync

## Problem Statement
How might we enable any family member to effortlessly see their upcoming meals, 
recipes, and cooking assignments on any calendar app in seconds, without requiring 
Google Cloud Console setup or API keys?

## Recommended Direction
Universal iCalendar (Webcal) Feeds:
- High-performance RFC 5545 `.ics` feed generated per household.
- 1-tap subscription for Apple Calendar (`webcal://`), 1-click for Google/Outlook.
- Two feed scopes:
  - **Household Feed:** All scheduled breakfasts, lunches, and dinners.
  - **Personalized Cook Feed:** Filtered to meals where a specific family member is the designated cook.
- Event summary includes meal type, recipe name, and cook name.
- Event body includes recipe prep/cook time, ingredients preview, and direct deep-link to the recipe in FamilyPlates.
- Secret unguessable token per household with 1-click regeneration.
- **Decision:** Deprecated and removed legacy Google Calendar Service Account direct sync in favor of universal subscription feeds. Universal feeds require zero API keys, zero cloud consoles, zero OAuth tokens, and work across Apple, Google, Outlook, Fastmail, Thunderbird, and mobile devices.

## User Experience (UX)
- A prominent **"📅 Subscribe to Calendar"** button on the Weekly Meal Planner header and inside Preferences.
- Clicking opens a clean modal with:
  - Tab 1: **"All Meals"** vs Tab 2: **"My Cooking Nights"** (defaults to current active profile).
  - One-click buttons:
    - 🍎 **Apple Calendar** (opens native Calendar app with subscription prompt).
    - 🌐 **Google Calendar** (opens Google Calendar web with pre-filled feed URL).
    - 📋 **Copy Feed URL** (with QR code for phone scanning from desktop).
- In Preferences/Admin: A "Calendar Subscriptions" card displaying feed URLs, copy shortcuts, and a "Regenerate Feed URL" security button.

## MVP Scope
1. **Schema:**
   - Add `calendar_feed_token` (string, indexed, unique) to `households`.
2. **Controller & Route:**
   - Public token-authenticated endpoint:
     `GET /calendars/feed/:token.ics` (all household meals for rolling -1 week to +4 weeks).
     `GET /calendars/feed/:token/members/:member_id.ics` (filtered to cook).
3. **Feed Serializer:**
   - Pure Ruby RFC 5545 generator with stable `UID`s based on `meal_plan_slot.id`, `DTSTART`, `DTEND` calculated from household meal times, description with ingredients, and `URL` linking back to the meal plan.
4. **UI:**
   - "Subscribe to Calendar" modal with 1-tap Apple, Google, and Outlook links + copy button.
   - Admin/Preferences controls to view the feed URL or reset the token.
5. **Caching:**
   - `stale?` checking using `household.meal_plan_slots.maximum(:updated_at)` for `304 Not Modified` responses.

## Not Doing (and Why)
- **Two-way CalDAV server:** Not accepting edits from external calendar apps back into FamilyPlates. Meal authoring, recipe tagging, and inventory belong in FamilyPlates; calendars are for visibility.
- **Requiring user logins for feed URLs:** Calendar subscription clients cannot pass web session cookies or basic auth prompts reliably; secure random URL tokens are the standard industry pattern.
