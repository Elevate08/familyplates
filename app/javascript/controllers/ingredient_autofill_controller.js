import { Controller } from "@hotwired/stimulus"
import { el, replaceChildren } from "helpers/dom"

function parseList(json) {
  if (!json) return []

  try {
    const parsed = JSON.parse(json)
    return Array.isArray(parsed) ? parsed : []
  } catch {
    return []
  }
}

export default class extends Controller {
  static targets = [
    "nameInput",
    "aisleSelect",
    "nameDropdown",
    "nameList",
    "createNameOption",
    "createNameText",
    "unitInput",
    "unitDropdown",
    "unitList",
    "createUnitOption",
    "createUnitText"
  ]

  // The catalogue lives on the form container, not on each row - a
  // twenty-ingredient recipe would otherwise ship twenty copies of it. Parsed
  // once per container and cached there, so twenty rows do not parse it twenty
  // times either.
  get ingredientsValue() {
    return this.catalogue.ingredients
  }

  get unitsValue() {
    return this.catalogue.units
  }

  get catalogue() {
    const host = this.element.closest("[data-ingredient-catalogue]")
    if (!host) return { ingredients: [], units: [] }

    if (!host.__ingredientCatalogue) {
      host.__ingredientCatalogue = {
        ingredients: parseList(host.dataset.ingredientCatalogueIngredients),
        units: parseList(host.dataset.ingredientCatalogueUnits)
      }
    }

    return host.__ingredientCatalogue
  }

  connect() {
    this._handleClickOutside = this.handleClickOutside.bind(this)
    document.addEventListener("click", this._handleClickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this._handleClickOutside)
  }

  // ==========================================
  // INGREDIENT NAME AUTOFILL & CREATION
  // ==========================================

  onNameFocus() {
    this.closeUnitDropdown()
    this.updateNameDropdown(this.nameInputTarget.value.trim())
  }

  onNameInput() {
    this.closeUnitDropdown()
    this.updateNameDropdown(this.nameInputTarget.value.trim())
  }

  onNameKeydown(event) {
    if (this.handleNavigationKey(event, "name")) return

    if (event.key === "Enter") {
      event.preventDefault()
      const highlighted = this.highlightedOption("name")
      if (highlighted?.dataset?.ingredientName) {
        this.selectIngredient(highlighted.dataset.ingredientName, highlighted.dataset.ingredientAisle)
        return
      }

      const query = this.nameInputTarget.value.trim()
      if (query.length === 0) return

      // Enter takes the best existing match. Creating something new needs a name
      // that matches nothing, or picking "Add" deliberately - otherwise typing
      // "Chick" and pressing Enter silently created a second ingredient called
      // "Chick" alongside the "Chicken" the household already knows.
      const chosen = this.highlightedOption("name") ||
                     (this.hasNameListTarget ? this.nameListTarget.querySelector("[data-ingredient-name]") : null)

      if (chosen?.dataset?.ingredientName) {
        this.selectIngredient(chosen.dataset.ingredientName, chosen.dataset.ingredientAisle)
      } else {
        this.createCustomIngredient(query)
      }
    } else if (event.key === "Escape") {
      this.closeNameDropdown()
    }
  }

  updateNameDropdown(query) {
    if (!this.hasNameDropdownTarget || !this.hasNameListTarget) return

    // Every re-render invalidates the highlight - the option it pointed at is gone.
    this.clearHighlight("name")

    const q = (query || "").toLowerCase()
    const matching = this.ingredientsValue.filter(item => {
      if (!q) return true
      return this.fuzzyMatch(q, item.name.toLowerCase())
    })

    this.nameListTarget.innerHTML = ""

    matching.slice(0, 8).forEach(item => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.tabIndex = -1
      btn.dataset.ingredientName = item.name
      btn.dataset.ingredientAisle = item.aisle
      btn.className = "w-full text-left px-3.5 py-2 rounded-2xl text-xs font-semibold text-slate-800 dark:text-slate-100 hover:bg-primary-50 dark:hover:bg-primary-950/60 hover:text-primary-600 dark:hover:text-primary-400 flex items-center justify-between transition-colors cursor-pointer"
      
      const aisleColor = this.getAisleBadgeColor(item.aisle)
      replaceChildren(btn,
        el("span", { className: "font-bold text-slate-900 dark:text-white truncate", text: item.name }),
        el("span", { className: `text-[10px] font-bold px-2 py-0.5 rounded-full ${aisleColor} shrink-0 ml-2 shadow-2xs`, text: item.aisle })
      )
      
      btn.addEventListener("click", (e) => {
        e.preventDefault()
        e.stopPropagation()
        this.selectIngredient(item.name, item.aisle)
      })

      this.nameListTarget.appendChild(btn)
    })

    // Check exact match for create option
    const exactMatch = this.ingredientsValue.some(i => i.name.toLowerCase() === q)
    if (q.length > 0 && !exactMatch) {
      if (this.hasCreateNameOptionTarget) this.createNameOptionTarget.classList.remove("hidden")
      if (this.hasCreateNameTextTarget) this.createNameTextTarget.textContent = query
    } else {
      if (this.hasCreateNameOptionTarget) this.createNameOptionTarget.classList.add("hidden")
    }

    const hasContent = matching.length > 0 || (q.length > 0 && !exactMatch)
    if (hasContent) {
      this.nameDropdownTarget.classList.remove("hidden")
    } else {
      this.nameDropdownTarget.classList.add("hidden")
    }
  }

  selectIngredient(name, aisle) {
    this.nameInputTarget.value = name

    if (aisle && this.hasAisleSelectTarget) {
      const select = this.aisleSelectTarget
      for (let i = 0; i < select.options.length; i++) {
        if (select.options[i].value.toLowerCase() === aisle.toLowerCase()) {
          select.selectedIndex = i
          break
        }
      }
      select.dispatchEvent(new Event("change", { bubbles: true }))
    }

    this.closeNameDropdown()
  }

  createCustomIngredient(query) {
    const trimmed = (query || this.nameInputTarget.value).trim()
    if (!trimmed) return

    this.nameInputTarget.value = trimmed

    const guessedAisle = this.guessAisle(trimmed)
    if (guessedAisle && this.hasAisleSelectTarget) {
      const select = this.aisleSelectTarget
      for (let i = 0; i < select.options.length; i++) {
        if (select.options[i].value.toLowerCase() === guessedAisle.toLowerCase()) {
          select.selectedIndex = i
          break
        }
      }
    }

    this.closeNameDropdown()
  }

  handleCreateNameClick(event) {
    event.preventDefault()
    event.stopPropagation()
    const query = this.nameInputTarget.value.trim()
    this.createCustomIngredient(query)
  }

  closeNameDropdown() {
    if (this.hasNameDropdownTarget) {
      this.nameDropdownTarget.classList.add("hidden")
    }
  }

  // ==========================================
  // MEASUREMENT UNIT AUTOFILL & CREATION
  // ==========================================

  onUnitFocus() {
    this.closeNameDropdown()
    this.updateUnitDropdown(this.unitInputTarget.value.trim())
  }

  onUnitInput() {
    this.closeNameDropdown()
    this.updateUnitDropdown(this.unitInputTarget.value.trim())
  }

  onUnitKeydown(event) {
    if (this.handleNavigationKey(event, "unit")) return

    if (event.key === "Enter") {
      event.preventDefault()
      const highlighted = this.highlightedOption("unit")
      if (highlighted?.dataset?.unitName) {
        this.selectUnit(highlighted.dataset.unitName)
        return
      }

      const query = this.unitInputTarget.value.trim()
      if (query.length === 0) return

      const chosen = this.highlightedOption("unit") ||
                     (this.hasUnitListTarget ? this.unitListTarget.querySelector("[data-unit-name]") : null)

      this.selectUnit(chosen?.dataset?.unitName || query)
    } else if (event.key === "Escape") {
      this.closeUnitDropdown()
    }
  }

  // --- Keyboard navigation and focus ------------------------------------------
  //
  // Both menus behave the same way, so the mechanics live here once. Arrow keys
  // move a highlight through the matches and on into the "Add" button, which is
  // the only way to create something that collides with an existing name.

  handleNavigationKey(event, kind) {
    if (event.key !== "ArrowDown" && event.key !== "ArrowUp") return false

    const options = this.optionsFor(kind)
    if (options.length === 0) return false

    event.preventDefault()

    const current = options.indexOf(this.highlightedOption(kind))
    const step = event.key === "ArrowDown" ? 1 : -1
    const next = current === -1
      ? (step === 1 ? 0 : options.length - 1)
      : (current + step + options.length) % options.length

    this.setHighlight(kind, options[next])
    return true
  }

  optionsFor(kind) {
    const list = kind === "name" ? this.nameListTarget : this.unitListTarget
    const create = kind === "name" ? this.createNameOptionTarget : this.createUnitOptionTarget
    const options = Array.from(list?.querySelectorAll("button") || [])

    if (create && !create.classList.contains("hidden")) {
      options.push(...create.querySelectorAll("button"))
    }

    return options
  }

  highlightedOption(kind) {
    return this.optionsFor(kind).find(option => option.dataset.highlighted === "true") || null
  }

  setHighlight(kind, option) {
    this.optionsFor(kind).forEach(candidate => {
      const active = candidate === option
      candidate.dataset.highlighted = active ? "true" : "false"
      candidate.classList.toggle("ring-2", active)
      candidate.classList.toggle("ring-primary-500", active)
    })

    option?.scrollIntoView({ block: "nearest" })
  }

  clearHighlight(kind) {
    this.setHighlight(kind, null)
  }

  // Closes both menus once focus has genuinely left the row, rather than moving
  // between the input and its own dropdown. They used to stay open behind
  // whatever the user tabbed to next.
  onFocusOut(event) {
    if (event.relatedTarget && this.element.contains(event.relatedTarget)) return

    this.closeNameDropdown()
    this.closeUnitDropdown()
  }

  updateUnitDropdown(query) {
    if (!this.hasUnitDropdownTarget || !this.hasUnitListTarget) return

    this.clearHighlight("unit")

    const q = (query || "").toLowerCase()
    const matching = this.unitsValue.filter(unit => {
      if (!q) return true
      return this.fuzzyMatch(q, unit.toLowerCase())
    })

    this.unitListTarget.innerHTML = ""

    matching.slice(0, 8).forEach(unit => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.tabIndex = -1
      btn.dataset.unitName = unit
      btn.className = "w-full text-left px-3.5 py-1.5 rounded-xl text-xs font-semibold text-slate-800 dark:text-slate-100 hover:bg-primary-50 dark:hover:bg-primary-950/60 hover:text-primary-600 dark:hover:text-primary-400 flex items-center justify-between transition-colors cursor-pointer"
      replaceChildren(btn,
        el("span", { className: "font-bold text-slate-900 dark:text-white", text: unit }),
        el("span", { className: "text-[10px] text-slate-400 font-medium", text: "Use" })
      )

      btn.addEventListener("click", (e) => {
        e.preventDefault()
        e.stopPropagation()
        this.selectUnit(unit)
      })

      this.unitListTarget.appendChild(btn)
    })

    // Exact match check for create unit option
    const exactMatch = this.unitsValue.some(u => u.toLowerCase() === q)
    if (q.length > 0 && !exactMatch) {
      if (this.hasCreateUnitOptionTarget) this.createUnitOptionTarget.classList.remove("hidden")
      if (this.hasCreateUnitTextTarget) this.createUnitTextTarget.textContent = query
    } else {
      if (this.hasCreateUnitOptionTarget) this.createUnitOptionTarget.classList.add("hidden")
    }

    const hasContent = matching.length > 0 || (q.length > 0 && !exactMatch)
    if (hasContent) {
      this.unitDropdownTarget.classList.remove("hidden")
    } else {
      this.unitDropdownTarget.classList.add("hidden")
    }
  }

  selectUnit(unit) {
    this.unitInputTarget.value = unit
    this.closeUnitDropdown()
  }

  handleCreateUnitClick(event) {
    event.preventDefault()
    event.stopPropagation()
    const query = this.unitInputTarget.value.trim()
    this.selectUnit(query)
  }

  closeUnitDropdown() {
    if (this.hasUnitDropdownTarget) {
      this.unitDropdownTarget.classList.add("hidden")
    }
  }

  // ==========================================
  // GENERAL UTILITIES
  // ==========================================

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.closeNameDropdown()
      this.closeUnitDropdown()
    }
  }

  fuzzyMatch(pattern, str) {
    if (!pattern) return true
    if (!str) return false
    if (str.includes(pattern)) return true

    let patternIdx = 0
    let strIdx = 0
    while (patternIdx < pattern.length && strIdx < str.length) {
      if (pattern[patternIdx] === str[strIdx]) {
        patternIdx++
      }
      strIdx++
    }
    return patternIdx === pattern.length
  }

  getAisleBadgeColor(aisle) {
    switch (aisle) {
      case "Produce":
        return "bg-emerald-100 dark:bg-emerald-950/80 text-emerald-800 dark:text-emerald-300 border border-emerald-200 dark:border-emerald-800"
      case "Meat & Seafood":
        return "bg-rose-100 dark:bg-rose-950/80 text-rose-800 dark:text-rose-300 border border-rose-200 dark:border-rose-800"
      case "Dairy & Refrigerated":
        return "bg-blue-100 dark:bg-blue-950/80 text-blue-800 dark:text-blue-300 border border-blue-200 dark:border-blue-800"
      case "Bakery":
        return "bg-amber-100 dark:bg-amber-950/80 text-amber-800 dark:text-amber-300 border border-amber-200 dark:border-amber-800"
      case "Pantry & Grains":
        return "bg-orange-100 dark:bg-orange-950/80 text-orange-800 dark:text-orange-300 border border-orange-200 dark:border-orange-800"
      case "Spices & Baking":
        return "bg-purple-100 dark:bg-purple-950/80 text-purple-800 dark:text-purple-300 border border-purple-200 dark:border-purple-800"
      case "Frozen":
        return "bg-cyan-100 dark:bg-cyan-950/80 text-cyan-800 dark:text-cyan-300 border border-cyan-200 dark:border-cyan-800"
      default:
        return "bg-slate-100 dark:bg-slate-800 text-slate-700 dark:text-slate-300 border border-slate-200 dark:border-slate-700"
    }
  }

  guessAisle(name) {
    const n = name.toLowerCase()
    if (/chicken|beef|pork|steak|turkey|salmon|fish|shrimp|bacon|sausage|meat/i.test(n)) return "Meat & Seafood"
    if (/milk|cream|cheese|cheddar|mozzarella|parmesan|butter|yogurt|egg/i.test(n)) return "Dairy & Refrigerated"
    if (/onion|garlic|tomato|potato|lettuce|pepper|spinach|carrot|broccoli|avocado|lime|lemon|cilantro|basil|parsley|cucumber|asparagus|zucchini|mushroom|celery/i.test(n)) return "Produce"
    if (/bread|tortilla|bun|pita|bagel|crust|roll/i.test(n)) return "Bakery"
    if (/flour|sugar|baking|salt|pepper|cumin|chili|oregano|paprika|cinnamon|vanilla|seasoning/i.test(n)) return "Spices & Baking"
    if (/frozen|peas|ice cream/i.test(n)) return "Frozen"
    if (/rice|pasta|spaghetti|noodle|oil|vinegar|soy sauce|broth|stock|canned|bean|honey|sauce|salsa/i.test(n)) return "Pantry & Grains"
    return "Other"
  }
}
