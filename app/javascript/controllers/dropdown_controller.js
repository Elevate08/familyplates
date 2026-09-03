import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "searchInput", "item", "group", "emptyState"]

  connect() {
    this._boundFilter = this.filter.bind(this)
  }

  toggle(event) {
    if (event) event.stopPropagation()
    const isOpening = this.menuTarget.classList.contains("hidden")
    this.menuTarget.classList.toggle("hidden")

    // Focused straight away rather than from a timer. A deferred focus outlives
    // the click that scheduled it: toggle twice quickly and the stale callback
    // lands after the menu has closed again, pulling the caret back into a menu
    // the reader has already dismissed.
    if (isOpening && this.hasSearchInputTarget) {
      this.searchInputTarget.focus()
    }
  }

  hide(event) {
    if (!this.element.contains(event.target)) {
      this.menuTarget.classList.add("hidden")
      if (this.hasSearchInputTarget) {
        this.searchInputTarget.value = ""
        this.filter()
      }
    }
  }

  filter() {
    if (!this.hasSearchInputTarget) return

    const query = this.searchInputTarget.value.toLowerCase().trim()
    const items = this.hasItemTargets ? this.itemTargets : Array.from(this.menuTarget.querySelectorAll("[data-dropdown-target~='item'], [data-dropdown-target='item']"))
    let visibleCount = 0

    items.forEach(item => {
      const text = (item.dataset.searchText || item.textContent || "").toLowerCase()
      const matches = !query || this.fuzzyMatch(query, text)

      if (matches) {
        item.classList.remove("hidden")
        item.style.display = ""
        visibleCount++
      } else {
        item.classList.add("hidden")
        item.style.display = "none"
      }
    })

    // Check groups visibility
    const groups = this.hasGroupTargets ? this.groupTargets : Array.from(this.menuTarget.querySelectorAll("[data-dropdown-target~='group'], [data-dropdown-target='group']"))
    if (groups.length > 0) {
      groups.forEach(group => {
        const groupItems = Array.from(group.querySelectorAll("[data-dropdown-target~='item'], [data-dropdown-target='item']"))
        const hasVisible = groupItems.some(el => el.style.display !== "none" && !el.classList.contains("hidden"))
        if (hasVisible) {
          group.classList.remove("hidden")
          group.style.display = ""
        } else {
          group.classList.add("hidden")
          group.style.display = "none"
        }
      })
    }

    // Toggle empty state
    if (this.hasEmptyStateTarget) {
      if (visibleCount === 0 && query !== "") {
        this.emptyStateTarget.classList.remove("hidden")
        this.emptyStateTarget.style.display = ""
      } else {
        this.emptyStateTarget.classList.add("hidden")
        this.emptyStateTarget.style.display = "none"
      }
    }
  }

  clearSearch(event) {
    if (event) event.preventDefault()
    if (this.hasSearchInputTarget) {
      this.searchInputTarget.value = ""
      this.searchInputTarget.focus()
      this.filter()
    }
  }

  fuzzyMatch(pattern, str) {
    if (!pattern) return true
    if (!str) return false
    
    // Direct substring check
    if (str.includes(pattern)) return true

    // Sequential letter matching (e.g. "bft" -> "breakfast", "chick" -> "chicken")
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
}
