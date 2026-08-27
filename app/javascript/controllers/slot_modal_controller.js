import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "modal",
    "mealTypeSelect",
    "timeInput",
    "recipeInput",
    "recipeDropdownButton",
    "recipeDropdownMenu",
    "recipeSelectedDisplay",
    "customTitleInput"
  ]

  static values = {
    breakfastTime: { type: String, default: "08:00" },
    lunchTime: { type: String, default: "12:30" },
    dinnerTime: { type: String, default: "18:00" },
    recipes: { type: Object, default: {} }
  }

  connect() {
    this.syncSelectedRecipeDisplay()
  }

  open(event) {
    if (event) {
      // Don't open modal if clicking on trash/delete button or recipe link
      if (event.target.closest("button[type='submit']") || event.target.closest("form") || event.target.closest("a")) {
        return
      }
      event.preventDefault()
    }

    if (this.hasModalTarget) {
      this.modalTarget.classList.remove("hidden")
      document.body.classList.add("overflow-hidden")
      this.syncSelectedRecipeDisplay()
    }
  }

  close(event) {
    if (event) event.preventDefault()
    if (this.hasModalTarget) {
      this.modalTarget.classList.add("hidden")
      document.body.classList.remove("overflow-hidden")
      this.hideRecipeDropdown()
    }
  }

  closeBackground(event) {
    if (event.target === this.modalTarget) {
      this.close(event)
    }
  }

  closeOnEsc(event) {
    if (event.key === "Escape" && this.hasModalTarget && !this.modalTarget.classList.contains("hidden")) {
      this.close(event)
    }
  }

  mealTypeChanged(event) {
    const newMealType = event.target.value
    if (!this.hasTimeInputTarget) return

    if (newMealType === "breakfast") {
      this.timeInputTarget.value = this.breakfastTimeValue || "08:00"
    } else if (newMealType === "lunch") {
      this.timeInputTarget.value = this.lunchTimeValue || "12:30"
    } else if (newMealType === "dinner") {
      this.timeInputTarget.value = this.dinnerTimeValue || "18:00"
    }
  }

  toggleRecipeDropdown(event) {
    if (event) event.preventDefault()
    if (this.hasRecipeDropdownMenuTarget) {
      this.recipeDropdownMenuTarget.classList.toggle("hidden")
    }
  }

  hideRecipeDropdown() {
    if (this.hasRecipeDropdownMenuTarget) {
      this.recipeDropdownMenuTarget.classList.add("hidden")
    }
  }

  closeRecipeDropdownOnOutside(event) {
    if (!this.hasRecipeDropdownMenuTarget || this.recipeDropdownMenuTarget.classList.contains("hidden")) return

    if (this.hasRecipeDropdownButtonTarget && this.recipeDropdownButtonTarget.contains(event.target)) return
    if (this.recipeDropdownMenuTarget.contains(event.target)) return

    this.hideRecipeDropdown()
  }

  selectRecipe(event) {
    if (event) event.preventDefault()
    const recipeId = event.currentTarget.dataset.recipeId || ""

    if (this.hasRecipeInputTarget) {
      this.recipeInputTarget.value = recipeId
    }

    this.syncSelectedRecipeDisplay()
    this.hideRecipeDropdown()
  }

  syncSelectedRecipeDisplay() {
    if (!this.hasRecipeInputTarget || !this.hasRecipeSelectedDisplayTarget) return

    const recipeId = this.recipeInputTarget.value
    const recipeData = this.recipesValue[recipeId]

    if (recipeData) {
      const tagsHtml = (recipeData.tags || []).slice(0, 3)
        .map(tag => `<span class="px-1.5 py-0.5 rounded-md bg-amber-50 border border-amber-200/80 text-amber-800 text-[9px] font-bold">${tag}</span>`)
        .join(" ")

      this.recipeSelectedDisplayTarget.innerHTML = `
        <div class="flex items-center gap-3 w-full text-left">
          <img src="${recipeData.image_url || 'https://images.unsplash.com/photo-1498837167922-ddd27525d352?auto=format&fit=crop&w=200&q=80'}"
               alt="${recipeData.title}"
               class="w-10 h-10 rounded-xl object-cover border border-slate-200 shadow-2xs shrink-0 bg-slate-100">
          <div class="flex-1 min-w-0">
            <div class="font-extrabold text-xs text-slate-900 truncate">${recipeData.title}</div>
            <div class="flex items-center gap-2 mt-0.5">
              <span class="text-[10px] font-bold text-slate-500">⏱️ ${recipeData.total_time || 30}m</span>
              <div class="flex flex-wrap gap-1">${tagsHtml}</div>
            </div>
          </div>
          <span class="text-xs text-slate-400 font-bold ml-2">▼</span>
        </div>
      `
    } else {
      this.recipeSelectedDisplayTarget.innerHTML = `
        <div class="flex items-center justify-between w-full text-left">
          <div class="flex items-center gap-2.5 text-slate-500 text-xs font-semibold">
            <span class="w-8 h-8 rounded-xl bg-slate-100 flex items-center justify-center text-sm border border-slate-200">📖</span>
            <span>-- Select Recipe or Enter Custom Dish Below --</span>
          </div>
          <span class="text-xs text-slate-400 font-bold ml-2">▼</span>
        </div>
      `
    }
  }
}
