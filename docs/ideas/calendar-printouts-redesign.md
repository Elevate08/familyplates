# Refrigerator Calendar Printouts Redesign

## Problem Statement
> **How Might We** create high-contrast, kitchen-glanceable Weekly and Monthly printouts for FamilyPlates where Breakfast, Lunch, and Dinner recipes are displayed with equal prominence, large legible typography, and assigned chef badges—engineered to fit flawlessly on a single standard 8.5×11 page?

---

## Recommended Direction

### 1. Weekly Printout: Landscape 4-Column Meal Matrix
* **Format:** Landscape orientation (`@page { size: landscape; margin: 0.35in; }`), engineered to utilize 100% of printable horizontal space.
* **Layout Structure:**
  * **Header:** Household name, formatted week dates, and a subtle kitchen quote / prep reminder.
  * **Matrix Grid:** 7 rows (Monday – Sunday) across 4 high-contrast columns:
    1. **Day Column (16% width):** Day of the week + date in extra-bold typography.
    2. **☀️ Breakfast (28% width):** Recipe title in high-contrast bold font (readable from across the room) + Chef badge.
    3. **🥪 Lunch (28% width):** Recipe title + Chef badge with distinct visual separation.
    4. **🍽️ Dinner (28% width):** Recipe title + Chef badge.
  * **Pen-Friendly Empty Slots:** Empty slots render a clean, subtle dotted line so family members can jot down quick notes or dining-out plans with a magnet pen.

### 2. Monthly Printout: 3-Tier Daily Recipe Matrix
* **Format:** Full-bleed landscape calendar grid fitting all 28–35 days on a single sheet without awkward page breaks.
* **Cell Architecture:**
  * **Day Header:** Bold date number with "Today" indicator if applicable.
  * **Tier 1 (☀️ B):** High-contrast breakfast line with bold recipe title + Chef pill.
  * **Tier 2 (🥪 L):** High-contrast lunch line with bold recipe title + Chef pill.
  * **Tier 3 (🍽️ D):** High-contrast dinner line with bold recipe title + Chef pill.
* **Dual Color & Monochrome Compatibility:** Uses clean borders and dark text contrast so the sheet is crisp on black-and-white laser printers as well as color inkjet printers.

---

## Key Assumptions to Validate
- [x] **1-Page Enforcement:** CSS `@media print` rules (`height: 100vh; overflow: hidden; page-break-inside: avoid`) guarantee zero accidental 2nd-page spillover across Chrome, Firefox, Safari, and Edge.
- [x] **Readability from 3–5 Feet:** Bold weights and font sizes (13–15pt on weekly view) allow family members to read the daily meals without walking up to the fridge.
- [x] **B&W Printer Legibility:** Light badge backgrounds and dark borders maintain high readability even without color ink.

---

## MVP Scope

| Included in MVP | Not Doing in v1 (and Why) |
|---|---|
| **Landscape 4-column weekly table** with equal B/L/D prominence | **Multi-week printing on one page** (cramming 2+ weeks makes font too small to read from across the kitchen) |
| **Full-width landscape monthly calendar** with 3 distinct meal tiers | **Full ingredient lists on printout** (belongs on the grocery checklist or mobile view, not a wall calendar) |
| **Prominent Chef badges & recipe titles** | **QR codes to each recipe** (clutters the visual layout of daily grid cells) |
| **CSS Print stylesheet** with `@page { size: landscape; }` & print button | |
| **Clean pen-friendly empty slots** | |
