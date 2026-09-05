# 📅 Universal Calendar Subscriptions

FamilyPlates provides **Universal Calendar Subscriptions** via standard iCalendar (`.ics` / `webcal://`) feeds. This allows every family member to subscribe to the household's live meal schedule directly from their phone, tablet, or desktop calendar app—with **zero API keys, zero cloud consoles, and zero OAuth configuration**.

---

## 🌟 Key Capabilities

* **1-Tap Apple Calendar Integration:** Click "1-Tap Subscribe" on macOS or iOS to instantly add the meal schedule as an auto-refreshing calendar.
* **1-Click Google Calendar Web Subscription:** Open Google Calendar on the web with the feed URL pre-populated for effortless addition.
* **Universal Application Compatibility:** Direct `.ics` feed URL works with Microsoft Outlook, Thunderbird, Fastmail, Proton Calendar, and native Android/iOS calendar clients.
* **Per-Cook Personal Shifts:** Family members can subscribe to either the entire family's meal schedule or only meals where they are assigned as the cook.
* **Automatic Live Updates:** When meals are planned, recipes swapped, or cooks reassigned, connected calendars automatically update on their normal refresh cycle.
* **Token Security & 1-Click Revocation:** Feeds are secured with high-entropy hex tokens. Admins can regenerate the token at any time to instantly revoke access to previous feeds.

---

## 📱 How to Subscribe

### From the Weekly Meal Planner
1. Navigate to the **Meal Planner** (`/`).
2. Click the **"Subscribe"** button with the calendar icon in the top header.
3. Choose your preferred feed view:
   * **Entire Household:** All scheduled meals for the family.
   * **My Cooking Shifts:** Filtered down to only meals where you are assigned as the cook.
4. Select your calendar app:
   * **Apple Calendar:** Click **1-Tap Subscribe** to launch Apple Calendar.
   * **Google Calendar:** Click **Subscribe on Web** to open Google Calendar with the feed URL.
   * **Other Calendars:** Click **Copy** next to the feed link, open your calendar app, and select *Add Calendar by URL* or *Subscribe to Calendar*.

### From Admin Settings
Admins can also view and manage calendar feeds from the Admin Control Center:
1. Navigate to **Admin Dashboard** (`/admin`).
2. Click **Calendar Subscriptions** (or visit `/admin/calendar/edit`).
3. View the household feed URL, test 1-tap subscription buttons, or rotate the feed token.

---

## 🔄 Feed Token Rotation & Security

If a device is lost, or you wish to revoke calendar access from external feeds:
1. Go to **Admin Control Center** > **Calendar Subscriptions**.
2. Scroll to the **Feed Link Security** section.
3. Click **Regenerate Feed Link** and confirm.
4. Existing external feeds will immediately receive a 404/expired response. Family members can simply re-subscribe using the new feed link.

---

## 🛠️ Technical Details

* **RFC 5545 Compliance:** Feeds are generated using standard iCalendar (`VCALENDAR` / `VEVENT`) formats.
* **Timezone Awareness:** All events reflect the household's configured timezone.
* **Event Details:** Calendar events include the meal name, planned date and slot (Breakfast, Lunch, Dinner), assigned cook name, prep notes, and direct links back to the recipe inside FamilyPlates.
* **HTTP Caching:** Feeds support `ETag` and `Last-Modified` headers to minimize bandwidth and server overhead when calendar clients poll for updates.
