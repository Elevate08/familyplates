import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "checkbox", "remaining", "offlineBadge", "copyButton", "copyButtonText"]
  static values = { planId: String, readOnly: Boolean }

  connect() {
    this.storageKey = `familyplates_checklist_${this.planIdValue || "current"}`
    this.restoreCheckedState()
    this.updateProgress()

    this.boundUpdateNetworkStatus = this.updateNetworkStatus.bind(this)
    window.addEventListener("online", this.boundUpdateNetworkStatus)
    window.addEventListener("offline", this.boundUpdateNetworkStatus)
    this.updateNetworkStatus()
  }

  disconnect() {
    window.removeEventListener("online", this.boundUpdateNetworkStatus)
    window.removeEventListener("offline", this.boundUpdateNetworkStatus)
  }

  updateNetworkStatus() {
    if (!this.hasOfflineBadgeTarget) return

    if (!navigator.onLine) {
      this.offlineBadgeTarget.classList.remove("hidden")
      this.offlineBadgeTarget.classList.add("inline-flex")
    } else {
      this.offlineBadgeTarget.classList.add("hidden")
      this.offlineBadgeTarget.classList.remove("inline-flex")
    }
  }

  toggle(event) {
    if (this.readOnlyValue) return

    const row = event.currentTarget.closest("[data-checklist-target='item']")
    const checkbox = row.querySelector("input[type='checkbox']")

    if (event.target !== checkbox) {
      checkbox.checked = !checkbox.checked
    }

    this.applyRowState(row, checkbox.checked)
    this.syncPantryStock(row, checkbox.checked)
    this.saveState()
    this.updateProgress()
  }

  // A restock line is the one kind of tick that means something off this page:
  // the staple has been bought, so it can go back to shielding itself from the
  // list. Un-ticking puts the flag back, because the usual reason to un-tick is
  // "I tapped the wrong row".
  //
  // Fire and forget. Both endpoints are idempotent, the checkbox state is
  // already saved locally, and a shopper standing in an aisle with no signal
  // must not be shown an error about the pantry.
  syncPantryStock(row, isChecked) {
    const url = isChecked ? row.dataset.restockUrl : row.dataset.markLowUrl
    if (!url) return

    fetch(url, {
      method: "PATCH",
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
      }
    }).catch(() => {})
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
    if (this.readOnlyValue) return

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
        if (Object.prototype.hasOwnProperty.call(checkedMap, cb.value)) {
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
    if (this.readOnlyValue) return

    const performReset = () => {
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

    if (window.showConfirmDialog) {
      window.showConfirmDialog("Reset all checkboxes for this grocery list?", {
        title: "Reset Grocery List",
        confirmText: "Reset Checklist",
        icon: "🔄"
      }).then(confirmed => {
        if (confirmed) performReset()
      })
    } else {
      if (confirm("Reset all checkboxes for this grocery list?")) {
        performReset()
      }
    }
  }

  updateProgress() {
    const uncheckedCount = this.checkboxTargets.filter(cb => !cb.checked).length
    if (this.hasRemainingTarget) {
      this.remainingTarget.textContent = uncheckedCount
    }
  }

  copyList() {
    const lines = []
    const subtitleEl = this.element.querySelector("p.text-xs")
    const weekLabel = subtitleEl ? subtitleEl.textContent.split("•")[0].trim() : "Shopping List"
    lines.push(`GROCERY LIST (${weekLabel})`)
    lines.push("")

    const sections = this.element.querySelectorAll(".space-y-6 > div")
    let totalItems = 0

    sections.forEach(section => {
      const aisleHeader = section.querySelector("h2 span:last-child")
      const aisleTitle = aisleHeader ? aisleHeader.textContent.trim() : null
      const rows = section.querySelectorAll("[data-checklist-target='item']")

      const aisleItems = []
      rows.forEach(row => {
        const checkbox = row.querySelector("input[type='checkbox']")
        const isChecked = checkbox && checkbox.checked
        const isStaple = row.dataset.isStaple === "true"
        const name = row.querySelector(".item-label")?.textContent?.trim()
        const qty = row.querySelector(".item-qty")?.textContent?.trim()

        if (name) {
          const checkMark = (isChecked || isStaple) ? "- [x]" : "- [ ]"
          let itemText = qty ? `${name} (${qty})` : name
          if (isStaple && !isChecked) {
            itemText += " (On Hand)"
          }
          aisleItems.push(`${checkMark} ${itemText}`)
          totalItems++
        }
      })

      if (aisleItems.length > 0 && aisleTitle) {
        lines.push(aisleTitle.toUpperCase())
        aisleItems.forEach(item => lines.push(item))
        lines.push("")
      }
    })

    if (totalItems === 0) {
      lines.push("No grocery items needed!")
    }

    const textToCopy = lines.join("\n").trim()
    if (navigator.clipboard) {
      navigator.clipboard.writeText(textToCopy).then(() => {
        this.showCopyFeedback()
      }).catch(err => {
        console.error("Clipboard copy failed:", err)
      })
    }
  }

  showCopyFeedback() {
    if (this.hasCopyButtonTextTarget) {
      const originalText = this.copyButtonTextTarget.textContent
      this.copyButtonTextTarget.textContent = "Copied Plain Text! 📋"
      setTimeout(() => {
        this.copyButtonTextTarget.textContent = originalText
      }, 2000)
    }
  }
}
