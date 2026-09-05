# Implementation Plan: Configurable Leftover Capacity & Shelf Life on Recipes

**Card:** [Fizzy #50](https://fizzy.app.davidspencer.xyz/1/cards/50)  
**Task list:** `tasks/todo.md`  

---

## Overview

Currently, FamilyPlates only has a binary `yields_leftovers` boolean on recipes. The weekly meal planner assumes a hardcoded 3-day window (`target_date - 3.days`) and allows unlimited leftover slots to be planned from a single cooked meal without tracking depletion.

This feature introduces two key capabilities to recipe leftovers:
1. **Configurable Leftover Capacity (Slot Count):** Define how many extra meal slots a cooked recipe yields (default 1, configurable up to 10). When a cooked meal is planned as leftovers, each planned leftover slot depletes available capacity. Once all leftover slots are planned, the dish is exhausted and disappears from leftover candidate suggestions.
2. **Configurable Shelf-Life Window (Days Good For):** Default to 3 days, but allow recipes to set their own shelf life (1–14 days). For example, seafood or delicate salads can expire after 1 day, while stews and chilis can remain eligible for 4–5 days.

---

## Architecture Decisions

### 1. Database Schema
- **`recipes` table:**
  - `leftover_capacity`: `integer, default: 1, null: false` (number of upcoming meal slots this dish can cover as leftovers).
  - `leftover_shelf_life_days`: `integer, default: 3, null: false` (number of days the dish remains fresh and eligible for leftovers).
- **`meal_plan_slots` table:**
  - `leftover_source_slot_id`: `bigint, null: true` (foreign key referencing `meal_plan_slots.id` with `on_delete: :nullify`).
  - Storing the exact cooking slot that originated the leftovers creates an explicit relationship between the cooked meal and its downstream leftover slots.

### 2. Association & Depletion Model
- In `MealPlanSlot`:
  - `belongs_to :leftover_source_slot, class_name: "MealPlanSlot", optional: true`
  - `has_many :leftover_slots, class_name: "MealPlanSlot", foreign_key: :leftover_source_slot_id, dependent: :nullify`
  - `leftover_capacity_remaining`: returns `(recipe&.leftover_capacity || 1) - leftover_slots.count`
- In `MealPlan#available_leftovers_for(target_date, target_meal_type)`:
  - Finds all non-leftover slots in the household with recipes where `yields_leftovers: true`.
  - Filters out slots where `target_date > slot.date + (slot.recipe.leftover_shelf_life_days || 3).days` (expired).
  - Filters out slots where `slot.date == target_date` and meal type rank >= target rank.
  - Filters out slots where `slot.leftover_slots.count >= (slot.recipe.leftover_capacity || 1)` (exhausted).
  - Sorts candidates by recipe yields preference, freshness (days ago), and meal rank difference.
  - Returns metadata including `source_slot_id`, `remaining_capacity`, and `days_remaining`.

### 3. User Interface
- **Recipe Edit Form (`app/views/recipes/_form.html.erb`):**
  - Under `yields_leftovers`, display interactive capacity input (1–10 meals) and shelf life input (1–14 days).
- **Recipe View (`app/views/recipes/show.html.erb`):**
  - Show descriptive badge: e.g. "🍱 Leftovers: 2 extra meals · Good for 4 days".
- **Slot Modal (`app/views/meal_plans/_slot.html.erb` & Stimulus `slot_modal_controller.js`):**
  - Leftover quick-pick buttons pass both `recipeId` and `sourceSlotId`.
  - Quick-pick buttons show remaining servings (`"2 left"`, `"Last one!"`) and shelf life status.

---

## Phase & Task List

### Phase 1: Foundation (Database & Models)
- [ ] **Task 1: Migration for Leftover Columns**
  - Add `leftover_capacity` and `leftover_shelf_life_days` to `recipes`.
  - Add `leftover_source_slot_id` with foreign key and index to `meal_plan_slots`.
- [ ] **Task 2: Model Validations and Associations**
  - Update `Recipe` with defaults and numericality validations for capacity and shelf life.
  - Update `MealPlanSlot` with self-referential `leftover_source_slot` and `leftover_slots` associations.

### Checkpoint: Foundation
- [ ] Migrations run cleanly up and down.
- [ ] Model tests verify associations and validations.

### Phase 2: Core Leftover Calculation Engine
- [ ] **Task 3: Dynamic Shelf-Life and Capacity Depletion Engine**
  - Update `MealPlan#available_leftovers_for` to filter out expired dishes (`date + shelf_life < target_date`).
  - Update `MealPlan#available_leftovers_for` to filter out exhausted dishes (`leftover_slots.count >= leftover_capacity`).
- [ ] **Task 4: Controller Parameters and Slot Persistence**
  - Update `RecipesController#recipe_params` to permit `:leftover_capacity` and `:leftover_shelf_life_days`.
  - Update `MealPlanSlotsController#slot_params` to permit `:leftover_source_slot_id`.

### Checkpoint: Engine
- [ ] Unit and integration tests verify leftover capacity depletion and shelf-life expiration.

### Phase 3: User Interface & Interactions
- [ ] **Task 5: Recipe Form & Recipe Details UI**
  - Add capacity and shelf-life fields to `app/views/recipes/_form.html.erb`.
  - Display leftover specs on `app/views/recipes/show.html.erb` and `_recipe_card.html.erb`.
- [ ] **Task 6: Meal Planner Slot Modal & Quick-Pick Buttons**
  - Update `app/views/meal_plans/_slot.html.erb` leftover candidate buttons with remaining capacity badges.
  - Update `app/javascript/controllers/slot_modal_controller.js` to set `leftover_source_slot_id` on selection.

### Checkpoint: UI & Interactions
- [ ] Modal planning correctly persists `leftover_source_slot_id`.
- [ ] When capacity is reached, candidate is no longer offered for subsequent slots.

### Phase 4: Verification & Fizzy Update
- [ ] **Task 7: Comprehensive Test Suite & System Tests**
  - Add system test verifying full flow: create recipe with 1 leftover capacity and 1-day shelf life -> plan dinner -> plan next day lunch -> verify lunch leftover works -> verify subsequent slots no longer offer it.
- [ ] **Task 8: Sync Fizzy Card #50**
  - Mark completed steps on Fizzy Card #50.

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Existing leftover slots lack `leftover_source_slot_id` | Low | Allow `leftover_source_slot_id` to be nullable; fallback logic gracefully handles legacy slots. |
| Deleting an original cooked slot | Low | `leftover_slots` association configured with `dependent: :nullify` so downstream leftover slots remain intact. |
| Moving a slot to a different date | Medium | `MealPlanSlot#move` preserves `leftover_source_slot_id` and re-evaluates validation. |
