## [v1.6.0] - 2026-10-15

Hearth now reaches the layout of the mockups, not just the palette, and leftovers stop masquerading as the next meal to cook.

### ⚠️ Upgrading from v1.5.0
* **No database migration.** Replace the image (and the worker container, if you run one) and the app boots on the same volume.

### 🍳 Cooking
* **Leftovers are no longer offered as the next thing to cook.** Cook Now, the planner's Cooking now / Up next banner and Cook Now's list of upcoming meals skip leftover slots, which were cooked at their source meal. When a day holds only leftovers, Cook Now says so instead of opening Cook Mode on them. The planner still shows leftovers with their Leftover badge, and grocery lists are unchanged.

### 🎨 Design
* Deeper Hearth visual rebuild toward the mockups: cookbook meal rows and recipe cards, cream navigation, spacious family settings and groceries, and warm Cook Mode panels. Existing routes, member accents, shopping weekday chips and hosted pricing are preserved.

