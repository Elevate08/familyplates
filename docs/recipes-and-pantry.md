# 🍳 Recipes & Pantry Management

FamilyPlates includes robust tools to import recipes from the web, build structured ingredient formulas, learn household supermarket aisle preferences, and maintain an active pantry inventory with the **Pantry Shield**.

---

## 🌐 1-Click Recipe Web Scraper

* **URL Importer:** Import recipes directly by pasting a URL from any major cooking site (supports all Schema.org / JSON-LD structured recipe formats).
* **Automatic Field Extraction:** Extracts title, description, prep/cook times, servings, instructions, ingredients, tags, and thumbnail images.
* **Smart Aisle Prediction:** Scraped ingredient strings are automatically parsed and assigned to the most likely supermarket aisle based on learned household history.

---

## 🥗 Structured Recipe Ingredient Editor

When adding or editing recipes manually or reviewing scraped recipes:

* **Four Distinct Fields per Ingredient:**
  1. **Quantity:** Numerical amount (e.g. `2`, `1.5`, `1/2`).
  2. **Measurement / Unit:** Standard and custom units (e.g. `tbsp`, `tsp`, `cup`, `g`, `oz`, `cloves`, `can`, `count`) with live autocomplete and instant creation.
  3. **Ingredient Name:** Searchable dropdown with fuzzy matching across existing household ingredients plus instant `✨ Add "[Name]"` creation.
  4. **Supermarket Aisle Category:** Direct aisle selector (Produce, Meat & Seafood, Dairy & Refrigerated, Bakery, Pantry & Grains, Spices & Baking, Frozen, Other).
* **Weighted Aisle Preference Learning:**
  * When you save a recipe, FamilyPlates tracks the ingredient-to-aisle mapping in `IngredientAisleMapping`.
  * The count strictly reflects actual saved recipes in your household.
  * When adding that ingredient to future recipes, the aisle selector automatically defaults to your family's most frequently assigned supermarket aisle.

---

## 🛡️ The Pantry Shield & On-Hand Inventory

Never double-buy items you already keep stocked in your kitchen:

* **On-Hand Status (Pantry Shield):**
  * Every item in your pantry features an interactive **Shield Icon button**.
  * **Amber Shield Checkmark (`On Hand`):** Item is in stock at home. Any recipes scheduled for the week requiring this item will be automatically shielded and omitted from your active supermarket shopping checklist.
  * **Outline Shield (`Need to Buy`):** Item is marked as out of stock. When called for by a recipe, it will appear on your grocery list.
* **Searchable Icon Picker:**
  * Floating `rounded-3xl` dropdown menu with live search filtering across custom SVG icons (pepper shaker, sugar bag, oil bottle, spice jar) and emojis.
* **Native Category Quick-Select:**
  * Fast peer-checked category pills with automatic heuristic detection as you type item names.

---

## 🛒 Aisle-Organized Grocery List

The Grocery List aggregates all ingredients required across the breakfast, lunch, and dinner recipes planned for a shopping period. With no dates chosen it shows the household's current shopping period: weekly, every 2 weeks or monthly. An organizer sets that in **Household & Meal Schedule** — a weekday for every week and every 2 weeks, a day of the month for every month (weekly on Saturday until changed). The period stays the same from one shopping day to the day before the next.

* **Any Shopping Period:** The bar under the title shows the dates covered and the number of meals to cook. Use the **This shop** (the current shopping period), **Next shop**, **This week**, **Next week**, **From today** (today to the end of the current shopping period, for a mid-period top-up), **This month** and **Next month** chips, or the arrows beside the dates. The arrows move to the previous or next shopping period when the list covers exactly one. Otherwise they move a whole month when the list covers one calendar month, and otherwise move by the length of the period. **Custom dates** takes any first and last day. A list covers at most 42 days; a longer request is cut to 42 days from the first day, and the page says so.
* **From the Planner:** The planner's week view has a **Grocery list** link for that week, and its month view links to that month. The grocery list's **Planner** link opens the week the list starts in.
* **Every Meal Counts:** A recipe planned on three days adds its ingredients three times. Leftover meals add nothing, because the dish was already cooked.
* **Aisle-Grouped Walk Order:** Categorized by Produce, Meat & Seafood, Dairy & Refrigerated, Bakery, Pantry & Grains, Spices & Baking, Frozen, and Other.
* **Unit Normalization & Aggregation:** Automatically sums matching ingredients (e.g. `2 tbsp olive oil` + `3 tbsp olive oil` = `5 tbsp olive oil`).
* **Interactive Mobile Checklist:** Checkbox that works offline (see below), with instant strikethrough, remaining item counter, and recipe source attribution. Ticks are remembered separately for each period.
* **Shared Ticks:** Ticks are shared by every device in the household, so two people can split the shopping and a tick made on one phone shows on the other (the list updates when you return to the tab or reopen the page; there is no live push). Only organizers can tick items or **Reset** the list (Reset clears the ticks for everyone); other members see the same ticks read-only. The same dates are the same list: a different period has its own ticks. A tick made without a connection is kept on that device and sent when it is back online; if two people change the same item, the later change wins. Ticks are not part of the household export.
* **Plain Text Copy:** 1-click clipboard export, headed with the period's dates, for messaging family members or pasting into store pickup apps.

## 📶 Using FamilyPlates Offline

Three areas work without a connection: the **grocery list**, **recipes** (including Cook Mode) and the **meal plan** (including its print view).

* A page is available offline after you have opened it on that device while online. Pages you have not opened yet are not saved. The Planner link and the app's start page show the plan you opened most recently.
* Pages with a filter or search in the address (for example a recipe search, or the month view) are not saved; the plain page is. The exception is a grocery list period: the eight most recently opened periods are saved.
* Recipe photos you uploaded are saved with the recipes that show them.
* Every other page needs a connection. Opened offline, it shows a short notice listing the three offline areas.
* Signing out, or switching to a profile in another household, clears the pages saved in that browser. It also resets the theme, grocery list ticks and Cook Mode progress stored there.
* The browser keeps saved pages only on HTTPS or `localhost`.
