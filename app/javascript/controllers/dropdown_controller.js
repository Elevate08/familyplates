import { Controller } from "@hotwired/stimulus"
import { fuzzyMatch } from "helpers/dom"

export default class extends Controller {
  static targets = ["menu", "searchInput", "item", "group", "emptyState"]

  connect() {
    this._boundFilter = this.filter.bind(this)
  }

  toggle(event) {
    if (event) event.stopPropagation()
    const isOpening = this.menuTarget.classList.contains("hidden")
    this.menuTarget.classList.toggle("hidden")

    // Focus now. A deferred focus outlives a second toggle and pulls the caret back into a closed menu.
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
      const matches = !query || fuzzyMatch(query, text)

      if (matches) {
        item.classList.remove("hidden")
        item.style.display = ""
        visibleCount++
      } else {
        item.classList.add("hidden")
        item.style.display = "none"
      }
    })

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

}
