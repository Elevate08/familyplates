import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "checkbox", "remaining"]
  static values = { planId: String }

  connect() {
    this.storageKey = `familyplates_checklist_${this.planIdValue || "current"}`
    this.restoreCheckedState()
    this.updateProgress()
  }

  toggle(event) {
    const row = event.currentTarget.closest("[data-checklist-target='item']")
    const checkbox = row.querySelector("input[type='checkbox']")

    if (event.target !== checkbox) {
      checkbox.checked = !checkbox.checked
    }

    this.applyRowState(row, checkbox.checked)
    this.saveState()
    this.updateProgress()
  }

  applyRowState(row, isChecked) {
    const textLabel = row.querySelector(".item-label")
    const isStaple = row.dataset.isStaple === "true"

    if (isChecked) {
      row.classList.add("opacity-50", "bg-slate-50")
      if (textLabel) textLabel.classList.add("line-through", "text-slate-400")
    } else {
      row.classList.remove("opacity-50")
      if (isStaple) {
        row.classList.remove("bg-slate-50")
        row.classList.add("bg-amber-50/40")
      } else {
        row.classList.remove("bg-slate-50")
        row.classList.add("bg-white")
      }
      if (textLabel) textLabel.classList.remove("line-through", "text-slate-400")
    }
  }

  saveState() {
    const checkedMap = {}
    this.checkboxTargets.forEach(cb => {
      checkedMap[cb.value] = cb.checked
    })
    try {
      localStorage.setItem(this.storageKey, JSON.stringify(checkedMap))
    } catch (e) {
      console.warn("Could not save checklist state", e)
    }
  }

  restoreCheckedState() {
    try {
      const saved = localStorage.getItem(this.storageKey)
      if (!saved) return
      const checkedMap = JSON.parse(saved)
      this.checkboxTargets.forEach(cb => {
        if (checkedMap.hasOwnProperty(cb.value)) {
          cb.checked = checkedMap[cb.value]
          const row = cb.closest("[data-checklist-target='item']")
          if (row) this.applyRowState(row, cb.checked)
        }
      })
    } catch (e) {
      console.warn("Could not restore checklist state", e)
    }
  }

  resetAll() {
    if (!confirm("Reset all checkboxes for this week?")) return
    this.checkboxTargets.forEach(cb => {
      const isStaple = cb.dataset.isStaple === "true"
      cb.checked = isStaple
      const row = cb.closest("[data-checklist-target='item']")
      if (row) this.applyRowState(row, cb.checked)
    })
    try {
      localStorage.removeItem(this.storageKey)
    } catch (e) {}
    this.updateProgress()
  }

  updateProgress() {
    const uncheckedCount = this.checkboxTargets.filter(cb => !cb.checked).length
    if (this.hasRemainingTarget) {
      this.remainingTarget.textContent = uncheckedCount
    }
  }
}
