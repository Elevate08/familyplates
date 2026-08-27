# FamilyPlates: Future Enhancements & Post-v1 Roadmap

This document outlines optional feature ideas and post-v1 enhancements for **FamilyPlates**, captured for future iteration and development.

---

## 1. Progressive Web App (PWA) & Offline Grocery Shopping
* **Problem:** Supermarkets often have spotty cellular reception in the back aisles where produce and dairy are located.
* **Concept:** Activate Rails 8 built-in PWA capabilities (`manifest.json` and service worker caching).
* **Key Features:**
  - One-tap "Add to Home Screen" prompt on iOS and Android with customized app icons.
  - Offline checklist functionality with automatic background sync when connection resumes.
  - Standalone app window styling (hides browser address bar on mobile devices).

---

## 2. 1-Tap Leftovers & Meal Rollover
* **Problem:** Families rarely cook from scratch 7 nights a week; dinners frequently yield lunch or dinner leftovers the following day.
* **Concept:** Quick slot action to link or copy previous meals without manually re-typing or searching.
* **Key Features:**
  - "Copy Last Night's Dinner to Today's Lunch" button on empty lunch slots.
  - "Cook Double Batch" toggle on dinner slots (automatically suggests scheduled leftovers on Day +1 or Day +2).
  - Visual leftover badge (🍱 Leftover) linking back to the original recipe.

---

## 3. Grocery List Quick-Share & Clipboard Exporter
* **Problem:** Sometimes a partner or roommate is already out near the grocery store and needs a quick copy of the remaining items.
* **Concept:** Format the live shopping checklist into a clean, copyable text summary for messaging apps.
* **Key Features:**
  - "Copy to Clipboard" button formatted by aisle with unchecked quantities.
  - Native iOS/Android Web Share API integration (1-tap send via iMessage, WhatsApp, Signal, or Slack).
  - Markdown/Plain-Text toggle for Apple Notes or Todoist import.

---

## 4. Kitchen Display / Ambient Fridge Kiosk Mode
* **Problem:** Families who keep an iPad, Android tablet, or Raspberry Pi screen mounted near the kitchen fridge want an ambient, always-on display.
* **Concept:** A distraction-free, high-contrast, touch-optimized kiosk dashboard.
* **Key Features:**
  - Auto-refreshing daily view with current time, today's dinner recipe photo, and the assigned Chef of the Night.
  - Glanceable weather / dinner prep countdown ("Dinner in 2 hours • Cook: Dad").
  - Dark mode and auto-dimming for late-night kitchen ambience.

---

## 5. Smart Pantry Depletion & Restock Prompts
* **Problem:** Items marked as "Always Stocked" in the Pantry Shield occasionally run out (e.g., olive oil or eggs empty mid-week).
* **Concept:** A fast 1-tap "We're Low on This" quick action accessible directly from the kitchen or recipe view.
* **Key Features:**
  - Quick "+ Low" button in the pantry view and recipe ingredient preview to temporarily unsuppress a staple onto the current week's grocery list.
  - Automatic re-stock reminder after weekly shopping is completed.

---

## 6. Family Dietary Preferences & Allergy Tagging
* **Problem:** Household members often have differing dietary constraints (e.g., gluten-free, vegetarian, nut allergy).
* **Concept:** Tag family member profiles with dietary preferences and show friendly warning badges on recipe cards.
* **Key Features:**
  - Member profile tags: *Gluten-Free*, *Dairy-Free*, *Vegetarian*, *Nut Allergy*.
  - Recipe compatibility indicators on weekly planner slots (e.g., "⚠️ Contains Dairy - Maya").
