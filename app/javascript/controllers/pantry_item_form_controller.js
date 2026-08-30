import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "nameInput",
    "categorySelect",
    "iconInput",
    "iconPreview",
    "pickerContainer",
    "categoryChip"
  ]

  connect() {
    this.manualCategorySelection = false
    const initialCategory = this.hasCategorySelectTarget && this.categorySelectTarget.value
      ? this.categorySelectTarget.value
      : "Spices & Baking"
    this.renderCategoryState(initialCategory)
  }

  onNameChange() {
    const name = this.nameInputTarget.value.trim().toLowerCase()
    if (!name) {
      this.manualCategorySelection = false
      return
    }

    // Auto-detect matching icon & category if user hasn't manually selected one
    if (!this.manualCategorySelection) {
      const detectedCategory = this.guessCategory(name)
      if (detectedCategory) {
        this.selectCategory(detectedCategory, false)
      }
    }

    // Auto-detect matching icon
    const detectedIcon = this.guessIcon(name)
    if (detectedIcon) {
      this.selectIconById(detectedIcon)
    }
  }

  togglePicker() {
    if (this.hasPickerContainerTarget) {
      this.pickerContainerTarget.classList.toggle("hidden")
    }
  }

  selectCategoryFromChip(event) {
    if (event) {
      event.preventDefault()
      event.stopPropagation()
    }
    const btn = event.target.closest("[data-category]") || event.currentTarget
    const cat = btn ? btn.getAttribute("data-category") : null
    if (cat) {
      this.manualCategorySelection = true
      this.selectCategory(cat, true)
    }
  }

  selectCategory(category, isManual = true) {
    if (!category) return
    if (isManual) this.manualCategorySelection = true

    if (this.hasCategorySelectTarget) {
      this.categorySelectTarget.value = category
      this.categorySelectTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }

    this.renderCategoryState(category)
  }

  renderCategoryState(category) {
    if (!this.hasCategoryChipTargets) return

    const activeClasses = [
      "bg-primary-600",
      "text-white",
      "border-primary-600",
      "shadow-sm",
      "scale-105"
    ]

    const inactiveClasses = [
      "bg-slate-100",
      "dark:bg-slate-800",
      "text-slate-700",
      "dark:text-slate-300",
      "border-slate-200",
      "dark:border-slate-700",
      "hover:border-slate-300",
      "dark:hover:border-slate-600"
    ]

    this.categoryChipTargets.forEach(chip => {
      const chipCat = chip.getAttribute("data-category")
      const isSelected = chipCat && chipCat.trim().toLowerCase() === category.trim().toLowerCase()

      if (isSelected) {
        inactiveClasses.forEach(cls => chip.classList.remove(cls))
        activeClasses.forEach(cls => chip.classList.add(cls))
        chip.setAttribute("aria-selected", "true")
      } else {
        activeClasses.forEach(cls => chip.classList.remove(cls))
        inactiveClasses.forEach(cls => chip.classList.add(cls))
        chip.setAttribute("aria-selected", "false")
      }
    })
  }

  pickIcon(event) {
    const btn = event.target.closest("[data-icon-id]") || event.currentTarget
    const iconId = btn ? btn.getAttribute("data-icon-id") : null
    if (iconId) {
      this.selectIconById(iconId)
    }
    if (this.hasPickerContainerTarget) {
      this.pickerContainerTarget.classList.add("hidden")
    }
  }

  selectIconById(iconId) {
    if (this.hasIconInputTarget) {
      this.iconInputTarget.value = iconId
    }
    if (this.hasIconPreviewTarget) {
      if (iconId === "pepper-shaker") {
        this.iconPreviewTarget.innerHTML = `<svg class="w-6 h-6 inline-block shrink-0" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M10 5C10 3.89543 10.8954 3 12 3H20C21.1046 3 22 3.89543 22 5V8H10V5Z" fill="#94A3B8"/><circle cx="13" cy="5.5" r="0.75" fill="#334155"/><circle cx="16" cy="5.5" r="0.75" fill="#334155"/><circle cx="19" cy="5.5" r="0.75" fill="#334155"/><path d="M8 9H24L22.5 27C22.3 28.1 21.3 29 20.2 29H11.8C10.7 29 9.7 28.1 9.5 27L8 9Z" fill="#CBD5E1" fill-opacity="0.3" stroke="#94A3B8" stroke-width="1.5"/><path d="M9.5 13H22.5L21.8 26C21.7 26.6 21.2 27 20.6 27H11.4C10.8 27 10.3 26.6 10.2 26L9.5 13Z" fill="#1E293B"/><circle cx="13" cy="17" r="1" fill="#475569"/><circle cx="17" cy="16" r="1.2" fill="#0F172A"/><circle cx="19" cy="20" r="1" fill="#475569"/><circle cx="14" cy="22" r="1.1" fill="#334155"/><circle cx="17" cy="24" r="0.9" fill="#0F172A"/><circle cx="12" cy="25" r="0.8" fill="#475569"/><path d="M11 11L12 25" stroke="white" stroke-width="1.2" stroke-linecap="round" stroke-opacity="0.6"/></svg>`
      } else if (iconId === "sugar-bag") {
        this.iconPreviewTarget.innerHTML = `<svg class="w-6 h-6 inline-block shrink-0" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M6 10C6 8.89543 6.89543 8 8 8H24C25.1046 8 26 8.89543 26 10L24.5 27C24.3 28.1 23.3 29 22.2 29H9.8C8.7 29 7.7 28.1 7.5 27L6 10Z" fill="#FEF3C7" stroke="#D97706" stroke-width="1.5"/><path d="M5 6C5 5.44772 5.44772 5 6 5H26C26.5523 5 27 5.44772 27 6V8C27 8.55228 26.5523 9 26 9H6C5.44772 9 5 8.55228 5 8V6Z" fill="#FDE68A" stroke="#D97706" stroke-width="1.5"/><rect x="9.5" y="14" width="13" height="9" rx="2" fill="#FFFFFF" stroke="#F59E0B" stroke-width="1"/><text x="16" y="20.5" font-family="system-ui, -apple-system, sans-serif" font-size="6.5" font-weight="900" fill="#D97706" text-anchor="middle">SUGAR</text><circle cx="21" cy="11.5" r="0.75" fill="#F59E0B"/><circle cx="11" cy="11.5" r="0.75" fill="#F59E0B"/></svg>`
      } else if (iconId === "oil-bottle") {
        this.iconPreviewTarget.innerHTML = `<svg class="w-6 h-6 inline-block shrink-0" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M14 2H18V6H14V2Z" fill="#F59E0B"/><path d="M13 6H19V9H13V6Z" fill="#D97706"/><path d="M11 11C11 9.89543 11.8954 9 13 9H19C20.1046 9 21 9.89543 21 11L22.5 27.5C22.6 28.3 22 29 21.2 29H10.8C10 29 9.4 28.3 9.5 27.5L11 11Z" fill="#FEF08A" stroke="#CA8A04" stroke-width="1.5"/><path d="M11.5 14H20.5L21.7 27.5C21.8 27.8 21.5 28 21.2 28H10.8C10.5 28 10.2 27.8 10.3 27.5L11.5 14Z" fill="#EAB308"/><path d="M16 18C15 19.5 14 20.5 14 21.5C14 22.6 14.9 23.5 16 23.5C17.1 23.5 18 22.6 18 21.5C18 20.5 17 19.5 16 18Z" fill="#CA8A04"/><path d="M13 13L12.5 25" stroke="white" stroke-width="1" stroke-linecap="round" stroke-opacity="0.8"/></svg>`
      } else if (iconId === "spice-jar") {
        this.iconPreviewTarget.innerHTML = `<svg class="w-6 h-6 inline-block shrink-0" viewBox="0 0 32 32" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M10 4C10 3.44772 10.4477 3 11 3H21C21.5523 3 22 3.44772 22 4V8H10V4Z" fill="#B45309"/><rect x="8" y="9" width="16" height="19" rx="3" fill="#F8FAFC" fill-opacity="0.4" stroke="#94A3B8" stroke-width="1.5"/><rect x="9.5" y="13" width="13" height="13.5" rx="1.5" fill="#FDE68A"/><rect x="8" y="16" width="16" height="7" fill="#FFFFFF" stroke="#CBD5E1" stroke-width="0.75"/><rect x="10.5" y="18.5" width="11" height="2" rx="1" fill="#64748B"/></svg>`
      } else {
        this.iconPreviewTarget.innerHTML = `<span class="text-xl select-none leading-none">${iconId}</span>`
      }
    }
  }

  guessCategory(name) {
    const n = name.toLowerCase()
    if (/chicken|beef|pork|steak|turkey|salmon|fish|shrimp|bacon|sausage|meat/i.test(n)) return "Meat & Seafood"
    if (/milk|cream|cheese|cheddar|mozzarella|parmesan|butter|yogurt|egg/i.test(n)) return "Dairy & Refrigerated"
    if (/onion|garlic|tomato|potato|lettuce|pepper|spinach|carrot|broccoli|avocado|lime|lemon|cilantro|basil|parsley|cucumber|asparagus|zucchini|mushroom|celery/i.test(n)) return "Produce"
    if (/bread|tortilla|bun|pita|bagel|crust|roll/i.test(n)) return "Bakery"
    if (/flour|sugar|baking|salt|pepper|cumin|chili|oregano|paprika|cinnamon|vanilla|seasoning|powder/i.test(n)) return "Spices & Baking"
    if (/frozen|peas|ice cream/i.test(n)) return "Frozen"
    if (/rice|pasta|spaghetti|noodle|oil|vinegar|soy sauce|broth|stock|canned|bean|honey|sauce|salsa/i.test(n)) return "Pantry & Grains"
    return null
  }

  guessIcon(name) {
    const n = name.toLowerCase()
    if (n.includes("black pepper") || n.includes("peppercorn") || n.includes("cracked pepper")) return "pepper-shaker"
    if (n.includes("sugar")) return "sugar-bag"
    if (n.includes("vegetable oil") || n.includes("canola oil") || n.includes("sunflower oil") || n.includes("cooking oil")) return "oil-bottle"
    if (n.includes("garlic powder") || n.includes("onion powder") || n.includes("seasoning") || n.includes("oregano") || n.includes("paprika") || n.includes("cumin") || n.includes("chili powder")) return "spice-jar"
    if (n.includes("olive oil") || n.includes("sesame oil")) return "🍾"
    if (n.includes("soy sauce")) return "🍶"
    if (n.includes("salt")) return "🧂"
    if (n.includes("flour")) return "🌾"
    if (n.includes("butter")) return "🧈"
    if (n.includes("egg")) return "🥚"
    if (n.includes("milk") || n.includes("cream")) return "🥛"
    if (n.includes("cheese") || n.includes("cheddar") || n.includes("mozzarella") || n.includes("parmesan")) return "🧀"
    if (n.includes("garlic")) return "🧄"
    if (n.includes("onion")) return "🧅"
    if (n.includes("rice")) return "🍚"
    if (n.includes("pasta") || n.includes("noodle") || n.includes("spaghetti")) return "🍝"
    if (n.includes("bread") || n.includes("toast") || n.includes("bun")) return "🍞"
    if (n.includes("honey") || n.includes("syrup")) return "🍯"
    if (n.includes("chicken") || n.includes("poultry")) return "🍗"
    if (n.includes("beef") || n.includes("steak") || n.includes("meat")) return "🥩"
    if (n.includes("fish") || n.includes("salmon") || n.includes("shrimp")) return "🐟"
    if (n.includes("tomato")) return "🍅"
    if (n.includes("lemon") || n.includes("lime")) return "🍋"
    if (n.includes("avocado")) return "🥑"
    if (n.includes("potato")) return "🥔"
    return null
  }
}
