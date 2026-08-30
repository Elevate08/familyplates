import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "hiddenInput",
    "textInput",
    "badgesContainer",
    "suggestionsMenu",
    "suggestionsList",
    "createOption",
    "createOptionText",
    "popularContainer"
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
        this.renderPopularTags()
      }
      this.hiddenInputTarget.addEventListener("change", this._handleHiddenInputChange)
    }

    this.renderBadges()
    this.renderPopularTags()
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
    this.renderPopularTags()
  }

  addTag(tag) {
    const trimmed = (tag || "").trim()
    if (!trimmed) return

    const current = this.getTags()
    // Case-insensitive check
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

  renderPopularTags() {
    if (!this.hasPopularContainerTarget) return
    const current = this.getTags().map(t => t.toLowerCase())
    const unselected = this.availableTagsValue.filter(t => !current.includes(t.toLowerCase())).slice(0, 10)

    this.popularContainerTarget.innerHTML = ""
    if (unselected.length === 0) return

    unselected.forEach(tag => {
      const btn = document.createElement("button")
      btn.type = "button"
      btn.className = "text-[11px] font-semibold px-2.5 py-1 rounded-full bg-slate-100 dark:bg-slate-800 hover:bg-primary-50 dark:hover:bg-primary-950/60 text-slate-600 dark:text-slate-300 hover:text-primary-700 dark:hover:text-primary-300 border border-slate-200 dark:border-slate-700 hover:border-primary-300 dark:hover:border-primary-700 transition-colors cursor-pointer"
      btn.textContent = `+ ${tag}`
      btn.addEventListener("click", (e) => {
        e.preventDefault()
        this.addTag(tag)
      })
      this.popularContainerTarget.appendChild(btn)
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
        // If there's a visible suggestion highlight or first match, add it; otherwise create tag
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

    // Filter available tags
    const matching = this.availableTagsValue.filter(tag => {
      const tagLower = tag.toLowerCase()
      if (current.includes(tagLower)) return false
      return !q || this.fuzzyMatch(q, tagLower)
    })

    this.suggestionsListTarget.innerHTML = ""

    // Render matches
    matching.slice(0, 8).forEach(tag => {
      const item = document.createElement("button")
      item.type = "button"
      item.dataset.tagItem = tag
      item.className = "w-full text-left px-3 py-2 rounded-xl text-xs font-semibold text-slate-800 dark:text-slate-100 hover:bg-primary-50 dark:hover:bg-primary-950/60 hover:text-primary-600 dark:hover:text-primary-400 flex items-center justify-between transition-colors cursor-pointer"
      item.innerHTML = `<span>🏷️ ${tag}</span><span class="text-[10px] text-slate-400 font-normal">Add</span>`
      item.addEventListener("click", (e) => {
        e.preventDefault()
        this.addTag(tag)
      })
      this.suggestionsListTarget.appendChild(item)
    })

    // Render create option if query is non-empty and not an exact match of existing tag
    const exactMatch = this.availableTagsValue.some(t => t.toLowerCase() === q)
    if (q.length > 0 && !exactMatch && !current.includes(q)) {
      this.createOptionTarget.classList.remove("hidden")
      this.createOptionTextTarget.textContent = query
    } else {
      this.createOptionTarget.classList.add("hidden")
    }

    // Toggle menu visibility
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
}
