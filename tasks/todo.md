# Tasks: Configurable Leftover Capacity & Shelf Life

**Implementation Plan:** `tasks/plan.md`  
**Card:** [Fizzy #50](https://fizzy.app.davidspencer.xyz/1/cards/50)

---

## Phase 1: Foundation (Database & Models)

### Task 1: Migration for Leftover Columns
**Description:** Create migration adding `leftover_capacity` and `leftover_shelf_life_days` to `recipes` and `leftover_source_slot_id` to `meal_plan_slots`.

**Acceptance criteria:**
- [x] `recipes` has `leftover_capacity` (integer, default: 1, null: false)
- [x] `recipes` has `leftover_shelf_life_days` (integer, default: 3, null: false)
- [x] `meal_plan_slots` has `leftover_source_slot_id` (bigint, null: true, indexed, foreign key to `meal_plan_slots(id)` with nullify on delete)

**Verification:**
- [x] `bin/rails db:migrate` succeeds
- [x] `bin/rails db:rollback && bin/rails db:migrate` succeeds

**Dependencies:** None  
**Files likely touched:**
- `db/migrate/*_add_leftover_attributes_to_recipes_and_slots.rb`
- `db/schema.rb`

---

### Task 2: Model Validations and Associations
**Description:** Update `Recipe` and `MealPlanSlot` with validations, associations, and helper methods.

**Acceptance criteria:**
- [x] `Recipe` validates `leftover_capacity` between 1 and 10 when `yields_leftovers?`
- [x] `Recipe` validates `leftover_shelf_life_days` between 1 and 14 when `yields_leftovers?`
- [x] `MealPlanSlot` defines `belongs_to :leftover_source_slot, class_name: "MealPlanSlot", optional: true`
- [x] `MealPlanSlot` defines `has_many :leftover_slots, class_name: "MealPlanSlot", foreign_key: :leftover_source_slot_id, dependent: :nullify`
- [x] `MealPlanSlot` defines `leftover_capacity_remaining` method

**Verification:**
- [x] `bin/rails test test/models/recipe_test.rb`
- [x] `bin/rails test test/models/meal_plan_slot_test.rb`

**Dependencies:** Task 1  
**Files likely touched:**
- `app/models/recipe.rb`
- `app/models/meal_plan_slot.rb`
- `test/models/recipe_test.rb`
- `test/models/meal_plan_slot_test.rb`

---

## Checkpoint: Foundation
- [x] All model tests pass: `bin/rails test test/models/recipe_test.rb test/models/meal_plan_slot_test.rb`

---

## Phase 2: Core Leftover Calculation Engine

### Task 3: Dynamic Shelf-Life and Capacity Depletion Engine
**Description:** Update `MealPlan#available_leftovers_for` to dynamically enforce recipe shelf life and capacity depletion.

**Acceptance criteria:**
- [x] A cooked meal slot is excluded when `target_date > slot.date + recipe.leftover_shelf_life_days.days`
- [x] A cooked meal slot is excluded when its `leftover_slots.count >= recipe.leftover_capacity`
- [x] Candidate payload includes `:source_slot_id`, `:remaining_capacity`, `:days_remaining`

**Verification:**
- [x] `bin/rails test test/models/meal_plan_test.rb`

**Dependencies:** Task 2  
**Files likely touched:**
- `app/models/meal_plan.rb`
- `test/models/meal_plan_test.rb`

---

### Task 4: Controller Parameters and Slot Persistence
**Description:** Permit leftover capacity and shelf life parameters in `RecipesController`, and permit `leftover_source_slot_id` in `MealPlanSlotsController`.

**Acceptance criteria:**
- [x] `RecipesController#recipe_params` permits `:leftover_capacity` and `:leftover_shelf_life_days`
- [x] `MealPlanSlotsController#slot_params` permits `:leftover_source_slot_id`
- [x] Saving a leftover slot correctly persists its `leftover_source_slot_id`

**Verification:**
- [x] `bin/rails test test/controllers/recipes_controller_test.rb`
- [x] `bin/rails test test/controllers/meal_plan_slots_controller_test.rb`

**Dependencies:** Task 3  
**Files likely touched:**
- `app/controllers/recipes_controller.rb`
- `app/controllers/meal_plan_slots_controller.rb`

---

## Checkpoint: Engine
- [x] Engine tests pass: `bin/rails test test/models/meal_plan_test.rb test/controllers/meal_plan_slots_controller_test.rb`

---

## Phase 3: User Interface & Interactions

### Task 5: Recipe Form & Recipe Details UI
**Description:** Add capacity and shelf-life input fields to the recipe edit/new form and display leftover specs on recipe cards.

**Acceptance criteria:**
- [x] Recipe form displays "Extra meals yielded" and "Good for (days)" inputs under the "Yields Leftovers" checkbox
- [x] Recipe show view displays leftover capacity and shelf life badge
- [x] Recipe index card displays leftover capacity badge

**Verification:**
- [x] `bin/rails test test/controllers/recipes_controller_test.rb`

**Dependencies:** Task 4  
**Files likely touched:**
- `app/views/recipes/_form.html.erb`
- `app/views/recipes/show.html.erb`
- `app/views/recipes/_recipe_card.html.erb`

---

### Task 6: Meal Plan Slot Modal & Quick-Pick Buttons
**Description:** Update `_slot.html.erb` and Stimulus `slot_modal_controller.js` to support selecting specific leftover source slots and showing remaining servings.

**Acceptance criteria:**
- [x] Leftover candidate buttons display remaining capacity (`"2 left"`, `"Last one!"`)
- [x] Clicking a leftover candidate sets both `recipe_id` and `leftover_source_slot_id`
- [x] Form submission persists `leftover_source_slot_id`

**Verification:**
- [x] Manual test on meal plan view and check slot persistence

**Dependencies:** Task 5  
**Files likely touched:**
- `app/views/meal_plans/_slot.html.erb`
- `app/javascript/controllers/slot_modal_controller.js`

---

## Checkpoint: UI & Interactions
- [x] Full user flow works end-to-end: creating recipe with custom leftovers -> planning meal -> picking leftover.

---

## Phase 4: Verification & Fizzy Update

### Task 7: Comprehensive Test Suite & System Tests
**Description:** Add system test for end-to-end leftover capacity depletion and shelf-life expiration.

**Acceptance criteria:**
- [x] System test verifies: recipe with capacity 1 only appears once as leftover; once planned, disappears from subsequent slots
- [x] System test verifies: recipe with 1-day shelf life does not appear on day 2 or 3
- [x] All 560+ unit, integration, and system tests pass with 0 errors

**Verification:**
- [x] `bin/rails test`
- [x] `bin/rails test:system`

**Dependencies:** Task 6  
**Files likely touched:**
- `test/system/meal_planner_test.rb`

---

### Task 8: Sync Fizzy Card #50
**Description:** Move card #50 to "In Progress" or "Done" based on user direction, and mark steps completed on Fizzy.

**Acceptance criteria:**
- [x] Fizzy Card #50 steps marked completed
- [x] Card status updated

**Dependencies:** Task 7
