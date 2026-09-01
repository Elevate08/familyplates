import { Controller } from "@hotwired/stimulus"
import { el, replaceChildren, chevron } from "helpers/dom"

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

  // image_url can arrive from a scraped third-party page, so anything that is
  // not a plain http(s) URL - javascript:, data:, a value with quotes in it -
  // falls back to the placeholder rather than reaching an src attribute.
  safeImageUrl(url) {
    const fallback = "https://images.unsplash.com/photo-1498837167922-ddd27525d352?auto=format&fit=crop&w=200&q=80"
    if (!url) return fallback

    try {
      const parsed = new URL(url, window.location.origin)
      return ["http:", "https:"].includes(parsed.protocol) ? parsed.href : fallback
    } catch {
      return fallback
    }
  }

  syncSelectedRecipeDisplay() {
    if (!this.hasRecipeInputTarget || !this.hasRecipeSelectedDisplayTarget) return

    const recipeId = this.recipeInputTarget.value
    const recipeData = this.recipesValue[recipeId]

    if (recipeData) {
      const tagBadges = (recipeData.tags || []).slice(0, 3).map(tag =>
        el("span", { className: "px-1.5 py-0.5 rounded-md bg-amber-50 border border-amber-200/80 text-amber-800 text-[9px] font-bold", text: tag })
      )

      replaceChildren(this.recipeSelectedDisplayTarget,
        el("div", { className: "flex items-center gap-3 w-full text-left" }, [
          el("img", {
            className: "w-10 h-10 rounded-xl object-cover border border-slate-200 shadow-2xs shrink-0 bg-slate-100",
            attrs: { src: this.safeImageUrl(recipeData.image_url), alt: recipeData.title || "" }
          }),
          el("div", { className: "flex-1 min-w-0" }, [
            el("div", { className: "font-extrabold text-xs text-slate-900 truncate", text: recipeData.title }),
            el("div", { className: "flex items-center gap-2 mt-0.5" }, [
              el("span", { className: "text-[10px] font-bold text-slate-500", text: `⏱️ ${recipeData.total_time || 30}m` }),
              el("div", { className: "flex flex-wrap gap-1" }, tagBadges)
            ])
          ]),
          chevron()
        ])
      )
    } else {
      replaceChildren(this.recipeSelectedDisplayTarget,
        el("div", { className: "flex items-center justify-between w-full text-left" }, [
          el("div", { className: "flex items-center gap-2.5 text-slate-500 text-xs font-semibold" }, [
            el("span", { className: "w-8 h-8 rounded-xl bg-slate-100 flex items-center justify-center text-sm border border-slate-200", text: "📖" }),
            el("span", { text: "-- Select Recipe or Enter Custom Dish Below --" })
          ]),
          chevron()
        ])
      )
    }
  }
}
