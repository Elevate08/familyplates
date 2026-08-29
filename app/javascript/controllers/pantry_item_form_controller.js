import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["nameInput", "categorySelect", "iconInput", "iconPreview", "pickerContainer", "categoryChip"]

  static values = {
    emojiMap: Object
  }

  connect() {
    this.popularIcons = [
      { id: "pepper-shaker", label: "Black Pepper", type: "svg", preview: "pepper-shaker" },
      { id: "sugar-bag", label: "Sugar Bag", type: "svg", preview: "sugar-bag" },
      { id: "oil-bottle", label: "Cooking Oil", type: "svg", preview: "oil-bottle" },
      { id: "spice-jar", label: "Spice Jar", type: "svg", preview: "spice-jar" },
      { id: "🧂", label: "Salt Shaker", type: "emoji", preview: "🧂" },
      { id: "🍾", label: "Olive Oil", type: "emoji", preview: "🍾" },
      { id: "🧈", label: "Butter", type: "emoji", preview: "🧈" },
      { id: "🥚", label: "Eggs", type: "emoji", preview: "🥚" },
      { id: "🥛", label: "Milk/Cream", type: "emoji", preview: "🥛" },
      { id: "🧀", label: "Cheese", type: "emoji", preview: "🧀" },
      { id: "🧄", label: "Fresh Garlic", type: "emoji", preview: "🧄" },
      { id: "🧅", label: "Fresh Onion", type: "emoji", preview: "🧅" },
      { id: "🍞", label: "Bread/Bakery", type: "emoji", preview: "🍞" },
      { id: "🍚", label: "Rice", type: "emoji", preview: "🍚" },
      { id: "🍝", label: "Pasta", type: "emoji", preview: "🍝" },
      { id: "🌾", label: "Flour/Grains", type: "emoji", preview: "🌾" },
      { id: "🌿", label: "Herbs/Seasoning", type: "emoji", preview: "🌿" },
      { id: "🍯", label: "Honey/Syrup", type: "emoji", preview: "🍯" },
      { id: "🍶", label: "Soy Sauce", type: "emoji", preview: "🍶" },
      { id: "🥩", label: "Meat/Beef", type: "emoji", preview: "🥩" },
      { id: "🍗", label: "Chicken/Poultry", type: "emoji", preview: "🍗" },
      { id: "🐟", label: "Fish/Seafood", type: "emoji", preview: "🐟" },
      { id: "🥬", label: "Greens/Produce", type: "emoji", preview: "🥬" },
      { id: "🍅", label: "Tomato", type: "emoji", preview: "🍅" },
      { id: "🍋", label: "Citrus/Lemon", type: "emoji", preview: "🍋" },
      { id: "🥑", label: "Avocado", type: "emoji", preview: "🥑" },
      { id: "🥔", label: "Potato", type: "emoji", preview: "🥔" },
      { id: "🧊", label: "Frozen/Ice", type: "emoji", preview: "🧊" }
    ]
  }

  onNameChange() {
    const name = this.nameInputTarget.value.trim().toLowerCase()
    if (!name) return

    // Auto-detect matching icon & category
    if (name.includes("black pepper") || name.includes("peppercorn") || name.includes("cracked pepper")) {
      this.selectIconById("pepper-shaker")
      this.selectCategory("Spices & Baking")
    } else if (name.includes("sugar")) {
      this.selectIconById("sugar-bag")
      this.selectCategory("Spices & Baking")
    } else if (name.includes("vegetable oil") || name.includes("canola oil") || name.includes("sunflower oil") || name.includes("cooking oil")) {
      this.selectIconById("oil-bottle")
      this.selectCategory("Pantry & Grains")
    } else if (name.includes("garlic powder") || name.includes("onion powder")) {
      this.selectIconById("spice-jar")
      this.selectCategory("Spices & Baking")
    } else if (name.includes("olive oil")) {
      this.selectIconById("🍾")
      this.selectCategory("Pantry & Grains")
    } else if (name.includes("soy sauce")) {
      this.selectIconById("🍶")
      this.selectCategory("Pantry & Grains")
    } else if (name.includes("salt")) {
      this.selectIconById("🧂")
      this.selectCategory("Spices & Baking")
    } else if (name.includes("flour")) {
      this.selectIconById("🌾")
      this.selectCategory("Spices & Baking")
    } else if (name.includes("butter")) {
      this.selectIconById("🧈")
      this.selectCategory("Dairy & Refrigerated")
    } else if (name.includes("egg")) {
      this.selectIconById("🥚")
      this.selectCategory("Dairy & Refrigerated")
    } else if (name.includes("milk") || name.includes("cream")) {
      this.selectIconById("🥛")
      this.selectCategory("Dairy & Refrigerated")
    } else if (name.includes("cheese")) {
      this.selectIconById("🧀")
      this.selectCategory("Dairy & Refrigerated")
    } else if (name.includes("garlic")) {
      this.selectIconById("🧄")
      this.selectCategory("Produce")
    } else if (name.includes("onion")) {
      this.selectIconById("🧅")
      this.selectCategory("Produce")
    } else if (name.includes("rice")) {
      this.selectIconById("🍚")
      this.selectCategory("Pantry & Grains")
    } else if (name.includes("pasta") || name.includes("noodle") || name.includes("spaghetti")) {
      this.selectIconById("🍝")
      this.selectCategory("Pantry & Grains")
    }
  }

  togglePicker() {
    if (this.hasPickerContainerTarget) {
      this.pickerContainerTarget.classList.toggle("hidden")
    }
  }

  selectCategoryFromChip(event) {
    const cat = event.currentTarget.dataset.category
    this.selectCategory(cat)
  }

  selectCategory(category) {
    if (this.hasCategorySelectTarget) {
      this.categorySelectTarget.value = category
    }
    if (this.hasCategoryChipTargets) {
      this.categoryChipTargets.forEach(chip => {
        if (chip.dataset.category === category) {
          chip.classList.add("bg-primary-600", "text-white", "border-primary-600")
          chip.classList.remove("bg-slate-100", "dark:bg-slate-800", "text-slate-700", "dark:text-slate-300", "border-slate-200", "dark:border-slate-700")
        } else {
          chip.classList.remove("bg-primary-600", "text-white", "border-primary-600")
          chip.classList.add("bg-slate-100", "dark:bg-slate-800", "text-slate-700", "dark:text-slate-300", "border-slate-200", "dark:border-slate-700")
        }
      })
    }
  }

  pickIcon(event) {
    const iconId = event.currentTarget.dataset.iconId
    this.selectIconById(iconId)
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
}
