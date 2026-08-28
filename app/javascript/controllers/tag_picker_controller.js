import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "tag"]

  connect() {
    this.highlightActiveTags()
  }

  toggle(event) {
    const pill = event.currentTarget
    const tagValue = pill.dataset.tagValue
    let currentTags = this.getTags()

    if (currentTags.includes(tagValue)) {
      currentTags = currentTags.filter(t => t !== tagValue)
    } else {
      currentTags.push(tagValue)
    }

    this.inputTarget.value = currentTags.join(", ")
    this.highlightActiveTags()
  }

  inputChanged() {
    this.highlightActiveTags()
  }

  getTags() {
    return this.inputTarget.value
      .split(",")
      .map(t => t.trim())
      .filter(t => t.length > 0)
  }

  highlightActiveTags() {
    const currentTags = this.getTags()
    this.tagTargets.forEach(pill => {
      const val = pill.dataset.tagValue
      if (currentTags.includes(val)) {
        pill.classList.add("bg-primary-500", "text-white", "border-primary-500")
        pill.classList.remove("bg-slate-100", "dark:bg-slate-800", "text-slate-700", "dark:text-slate-300", "border-slate-200", "dark:border-slate-700")
      } else {
        pill.classList.remove("bg-primary-500", "text-white", "border-primary-500")
        pill.classList.add("bg-slate-100", "dark:bg-slate-800", "text-slate-700", "dark:text-slate-300", "border-slate-200", "dark:border-slate-700")
      }
    })
  }
}
