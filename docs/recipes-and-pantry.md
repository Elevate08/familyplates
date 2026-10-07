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

The Grocery List aggregates all ingredients required across scheduled breakfast, lunch, and dinner recipes for the week:

* **Aisle-Grouped Walk Order:** Categorized by Produce, Meat & Seafood, Dairy & Refrigerated, Bakery, Pantry & Grains, Spices & Baking, Frozen, and Other.
* **Unit Normalization & Aggregation:** Automatically sums matching ingredients (e.g. `2 tbsp olive oil` + `3 tbsp olive oil` = `5 tbsp olive oil`).
* **Interactive Mobile Checklist:** Checkbox that works offline (see below), with instant strikethrough, remaining item counter, and recipe source attribution.
* **Plain Text Copy:** 1-click clipboard export for messaging family members or pasting into store pickup apps.

## 📶 Using FamilyPlates Offline

Three areas work without a connection: the **grocery list**, **recipes** (including Cook Mode) and the **meal plan** (including its print view).

* A page is available offline after you have opened it on that device while online. Pages you have not opened yet are not saved. The Planner link and the app's start page show the plan you opened most recently.
* Pages with a filter or search in the address (for example a recipe search, or the month view) are not saved; the plain page is.
* Recipe photos you uploaded are saved with the recipes that show them.
* Every other page needs a connection. Opened offline, it shows a short notice listing the three offline areas.
* Signing out, or switching to a profile in another household, clears the pages saved in that browser. It also resets the theme, grocery list ticks and Cook Mode progress stored there.
* The browser keeps saved pages only on HTTPS or `localhost`.
