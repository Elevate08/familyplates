import { Controller } from "@hotwired/stimulus"
import { el, replaceChildren, fuzzyMatch } from "helpers/dom"

export default class extends Controller {
  static targets = [
    "hiddenInput",
    "textInput",
    "badgesContainer",
    "suggestionsMenu",
    "suggestionsList",
    "createOption",
    "createOptionText"
  ]

  static values = {
    availableTags: { type: Array, default: [] }
  }

  connect() {
    this._handleClickOutside = this.handleClickOutside.bind(this)
    document.addEventListener("click", this._handleClickOutside)

    if (this.hasHiddenInputTarget) {
      this._handleHiddenInputChange = () => {
        this.renderBadges()
      }
      this.hiddenInputTarget.addEventListener("change", this._handleHiddenInputChange)
    }

    this.renderBadges()
  }

  disconnect() {
    document.removeEventListener("click", this._handleClickOutside)
    if (this.hasHiddenInputTarget && this._handleHiddenInputChange) {
      this.hiddenInputTarget.removeEventListener("change", this._handleHiddenInputChange)
    }
  }

  getTags() {
    if (!this.hasHiddenInputTarget || !this.hiddenInputTarget.value) return []
    return this.hiddenInputTarget.value
      .split(",")
      .map(t => t.trim())
      .filter(t => t.length > 0)
  }

  setTags(tags) {
    const unique = Array.from(new Set(tags.map(t => t.trim()))).filter(t => t.length > 0)
    this.hiddenInputTarget.value = unique.join(", ")
    this.renderBadges()
  }

  addTag(tag) {
    const trimmed = (tag || "").trim()
    if (!trimmed) return

    const current = this.getTags()
    const exists = current.some(t => t.toLowerCase() === trimmed.toLowerCase())
    if (!exists) {
      current.push(trimmed)
      this.setTags(current)
    }

    if (this.hasTextInputTarget) {
      this.textInputTarget.value = ""
      this.textInputTarget.focus()
    }
    this.closeSuggestions()
  }

  removeTag(event) {
    event.preventDefault()
    event.stopPropagation()
    const tagToRemove = event.currentTarget.dataset.tag
    const current = this.getTags().filter(t => t.toLowerCase() !== tagToRemove.toLowerCase())
    this.setTags(current)
    if (this.hasTextInputTarget) {
      this.textInputTarget.focus()
    }
  }

  renderBadges() {
    if (!this.hasBadgesContainerTarget) return

    const current = this.getTags()
    this.badgesContainerTarget.innerHTML = ""

    current.forEach(tag => {
      const badge = document.createElement("span")
      badge.className = "inline-flex items-center gap-1.5 px-3 py-1 rounded-xl bg-primary-50 dark:bg-primary-950/60 text-primary-700 dark:text-primary-300 border border-primary-200 dark:border-primary-800 text-xs font-bold shadow-2xs group animate-in fade-in zoom-in-95 duration-100"
      
      const textSpan = document.createElement("span")
      textSpan.textContent = tag
      badge.appendChild(textSpan)

      const removeBtn = document.createElement("button")
      removeBtn.type = "button"
      removeBtn.dataset.tag = tag
      removeBtn.dataset.action = "click->tag-picker#removeTag"
      removeBtn.className = "w-4 h-4 rounded-full flex items-center justify-center text-primary-400 hover:text-primary-700 dark:hover:text-white hover:bg-primary-200/60 dark:hover:bg-primary-800/60 transition-colors cursor-pointer"
      removeBtn.innerHTML = "&times;"
      removeBtn.title = `Remove ${tag}`
      badge.appendChild(removeBtn)

      this.badgesContainerTarget.appendChild(badge)
    })
  }


  focusInput(event) {
    if (this.hasTextInputTarget && event.target !== this.textInputTarget) {
      this.textInputTarget.focus()
    }
  }

  onInput(event) {
    const query = this.textInputTarget.value.trim()
    this.updateSuggestions(query)
  }

  onKeydown(event) {
    if (event.key === "Enter" || event.key === ",") {
      event.preventDefault()
      const query = this.textInputTarget.value.trim().replace(/,$/, "")
      if (query.length > 0) {
        const firstMatch = this.suggestionsListTarget.querySelector("[data-tag-item]")
        if (firstMatch && firstMatch.dataset.tagItem.toLowerCase() === query.toLowerCase()) {
          this.addTag(firstMatch.dataset.tagItem)
        } else {
          this.addTag(query)
        }
      }
    } else if (event.key === "Backspace" && this.textInputTarget.value === "") {
      const current = this.getTags()
      if (current.length > 0) {
        current.pop()
        this.setTags(current)
      }
    } else if (event.key === "Escape") {
      this.closeSuggestions()
    }
  }

  updateSuggestions(query) {
    if (!this.hasSuggestionsMenuTarget) return

    const current = this.getTags().map(t => t.toLowerCase())
    const q = (query || "").toLowerCase()

    const matching = this.availableTagsValue.filter(tag => {
      const tagLower = tag.toLowerCase()
      if (current.includes(tagLower)) return false
      return !q || fuzzyMatch(q, tagLower)
    })

    this.suggestionsListTarget.innerHTML = ""

    matching.slice(0, 8).forEach(tag => {
      const item = document.createElement("button")
      item.type = "button"
      item.dataset.tagItem = tag
      item.className = "w-full text-left px-3 py-2 rounded-xl text-xs font-semibold text-slate-800 dark:text-slate-100 hover:bg-primary-50 dark:hover:bg-primary-950/60 hover:text-primary-600 dark:hover:text-primary-400 flex items-center justify-between transition-colors cursor-pointer"
      replaceChildren(item,
        el("span", { text: `🏷️ ${tag}` }),
        el("span", { className: "text-[10px] text-slate-400 font-normal", text: "Add" })
      )
      item.addEventListener("click", (e) => {
        e.preventDefault()
        this.addTag(tag)
      })
      this.suggestionsListTarget.appendChild(item)
    })

    const exactMatch = this.availableTagsValue.some(t => t.toLowerCase() === q)
    if (q.length > 0 && !exactMatch && !current.includes(q)) {
      this.createOptionTarget.classList.remove("hidden")
      this.createOptionTextTarget.textContent = query
    } else {
      this.createOptionTarget.classList.add("hidden")
    }

    const hasItems = matching.length > 0 || (q.length > 0 && !exactMatch)
    if (hasItems) {
      this.suggestionsMenuTarget.classList.remove("hidden")
    } else {
      this.suggestionsMenuTarget.classList.add("hidden")
    }
  }

  createCustomTag(event) {
    event.preventDefault()
    const query = this.textInputTarget.value.trim()
    if (query) {
      this.addTag(query)
    }
  }

  onFocus() {
    this.updateSuggestions(this.textInputTarget.value.trim())
  }

  closeSuggestions() {
    if (this.hasSuggestionsMenuTarget) {
      this.suggestionsMenuTarget.classList.add("hidden")
    }
  }

  handleClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.closeSuggestions()
    }
  }

}
