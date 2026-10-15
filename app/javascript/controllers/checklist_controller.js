import { Controller } from "@hotwired/stimulus"

// The grocery checklist. Ticks are shared by the household's devices: the server
// renders the saved ticks, every tick is sent to the server, and the page asks for
// the list's ticks again whenever it is shown or regains focus. localStorage keeps
// an offline copy and the queue of changes the server has not acknowledged yet.
const PENDING_KEY = "familyplates_pending_ticks"

export default class extends Controller {
  static targets = ["item", "checkbox", "remaining", "offlineBadge", "copyButton", "copyButtonText"]
  static values = { from: String, to: String, rangeLabel: String, readOnly: Boolean, ticksUrl: String }

  connect() {
    this.storageKey = `familyplates_checklist_${this.fromValue}_${this.toValue}`
    this.changeCount = 0
    this.flushing = false

    // Online, the server-rendered ticks are the truth. Offline, the page may be an old
    // saved copy, so the ticks this device last saw are laid over it.
    if (!navigator.onLine) this.restoreCheckedState()
    this.applyPending()
    this.updateProgress()

    this.boundOnline = () => { this.updateNetworkStatus(); this.sync() }
    this.boundOffline = () => this.updateNetworkStatus()
    this.boundShown = () => { if (document.visibilityState === "visible") this.sync() }
    window.addEventListener("online", this.boundOnline)
    window.addEventListener("offline", this.boundOffline)
    window.addEventListener("focus", this.boundShown)
    document.addEventListener("visibilitychange", this.boundShown)
    this.updateNetworkStatus()
    this.sync()
  }

  disconnect() {
    window.removeEventListener("online", this.boundOnline)
    window.removeEventListener("offline", this.boundOffline)
    window.removeEventListener("focus", this.boundShown)
    document.removeEventListener("visibilitychange", this.boundShown)
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

    this.changeCount++
    this.applyRowState(row, checkbox.checked)
    this.syncPantryStock(row, checkbox.checked)
    this.saveState()
    this.updateProgress()
    this.enqueue({
      from: this.fromValue, to: this.toValue, item_key: checkbox.value,
      checked: checkbox.checked, changed_at: new Date().toISOString()
    })
    this.flush()
  }

  // ---- Shared ticks ----

  jsonHeaders() {
    return {
      "Accept": "application/json",
      "Content-Type": "application/json",
      "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
    }
  }

  readPending() {
    try {
      const list = JSON.parse(localStorage.getItem(PENDING_KEY) || "[]")
      return Array.isArray(list) ? list : []
    } catch (e) {
      return []
    }
  }

  writePending(list) {
    try {
      if (list.length) localStorage.setItem(PENDING_KEY, JSON.stringify(list))
      else localStorage.removeItem(PENDING_KEY)
    } catch (e) {
      console.warn("Could not save pending grocery ticks", e)
    }
  }

  sameItem(a, b) {
    return a.from === b.from && a.to === b.to && a.item_key === b.item_key
  }

  // One queued change per item and list: a newer change replaces an unsent older one.
  enqueue(change) {
    this.writePending(this.readPending().filter((c) => !this.sameItem(c, change)).concat(change))
  }

  // Only the exact change that was sent: one made since stays queued.
  dequeue(change) {
    this.writePending(this.readPending().filter((c) => !(this.sameItem(c, change) && c.changed_at === change.changed_at)))
  }

  pendingForThisList() {
    return this.readPending().filter((c) => c.from === this.fromValue && c.to === this.toValue)
  }

  applyPending() {
    if (this.readOnlyValue) return
    const byKey = new Map(this.pendingForThisList().map((c) => [c.item_key, c.checked]))
    this.checkboxTargets.forEach((cb) => {
      if (byKey.has(cb.value)) this.setChecked(cb, byKey.get(cb.value))
    })
  }

  setChecked(checkbox, isChecked) {
    if (checkbox.checked === isChecked) return
    checkbox.checked = isChecked
    const row = checkbox.closest("[data-checklist-target='item']")
    if (row) this.applyRowState(row, isChecked)
  }

  // Send what is waiting, then fetch the list's current ticks.
  async sync() {
    await this.flush()
    await this.refresh()
  }

  // Sends queued changes in order. A network failure or server error leaves the rest queued
  // (they are retried on the next online / visible event); a refusal (403, 422) can never
  // succeed, so it is dropped.
  async flush() {
    if (this.readOnlyValue || this.flushing || !this.ticksUrlValue || !navigator.onLine) return
    this.flushing = true
    const tried = new Set()
    try {
      for (;;) {
        const change = this.readPending().find((c) => !tried.has(`${c.from}|${c.to}|${c.item_key}|${c.changed_at}`))
        if (!change) break
        tried.add(`${change.from}|${change.to}|${change.item_key}|${change.changed_at}`)

        let response
        try {
          response = await fetch(this.ticksUrlValue, {
            method: "PUT", headers: this.jsonHeaders(), credentials: "same-origin", body: JSON.stringify(change)
          })
        } catch (e) {
          break
        }
        if (response.ok) {
          this.dequeue(change)
          await this.adoptServerAnswer(change, response)
        } else if (response.status === 403 || response.status === 422) {
          this.dequeue(change)
        } else {
          break
        }
      }
    } finally {
      this.flushing = false
    }
  }

  // If a newer change from another device won, show what stands (unless this device has changed it again).
  async adoptServerAnswer(change, response) {
    if (change.from !== this.fromValue || change.to !== this.toValue) return
    try {
      const answer = await response.json()
      if (this.pendingForThisList().some((c) => c.item_key === change.item_key)) return
      const checkbox = this.checkboxTargets.find((cb) => cb.value === change.item_key)
      if (checkbox && typeof answer.checked === "boolean") {
        this.setChecked(checkbox, answer.checked)
        this.saveState()
        this.updateProgress()
      }
    } catch (e) {}
  }

  // Applies the server's ticks for this list. An item with no tick goes back to its default (staples are on hand).
  async refresh() {
    if (!this.ticksUrlValue || !navigator.onLine) return
    const startedAt = this.changeCount
    try {
      const query = new URLSearchParams({ from: this.fromValue, to: this.toValue })
      const response = await fetch(`${this.ticksUrlValue}?${query}`, {
        headers: { "Accept": "application/json" }, credentials: "same-origin"
      })
      if (!response.ok) return
      const { ticks } = await response.json()
      // A tick made while this was in flight is newer than the answer.
      if (!ticks || startedAt !== this.changeCount) return

      const pending = new Set(this.pendingForThisList().map((c) => c.item_key))
      this.checkboxTargets.forEach((cb) => {
        if (pending.has(cb.value)) return
        const value = Object.prototype.hasOwnProperty.call(ticks, cb.value) ? ticks[cb.value] : cb.dataset.isStaple === "true"
        this.setChecked(cb, value)
      })
      this.saveState()
      this.updateProgress()
    } catch (e) {
      // Offline or the server is away: keep what is shown.
    }
  }

  // Ticking a restock line means the staple was bought and can shield itself again.
  // Fire and forget: the endpoints are idempotent, and a shopper with no signal must not see an error.
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

  // The offline copy: what this device last showed for the list.
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
          this.setChecked(cb, checkedMap[cb.value])
        }
      })
    } catch (e) {
      console.warn("Could not restore checklist state", e)
    }
  }

  resetAll() {
    if (this.readOnlyValue) return

    // Clears the list on the server first: the ticks go for everyone, and a reset
    // that never reached the server would come straight back on the next refresh.
    const performReset = async () => {
      try {
        const response = await fetch(this.ticksUrlValue, {
          method: "DELETE", headers: this.jsonHeaders(), credentials: "same-origin",
          body: JSON.stringify({ from: this.fromValue, to: this.toValue })
        })
        if (!response.ok) throw new Error(`reset refused: ${response.status}`)
      } catch (e) {
        alert("Couldn't reset the list. Check your connection and try again.")
        return
      }

      this.changeCount++
      this.writePending(this.readPending().filter((c) => !(c.from === this.fromValue && c.to === this.toValue)))
      this.checkboxTargets.forEach(cb => {
        this.setChecked(cb, cb.dataset.isStaple === "true")
      })
      try {
        localStorage.removeItem(this.storageKey)
      } catch (e) {}
      this.updateProgress()
    }

    if (window.showConfirmDialog) {
      window.showConfirmDialog("Reset all checkboxes for this grocery list? This clears them for everyone in the household.", {
        title: "Reset Grocery List",
        confirmText: "Reset Checklist",
        icon: "🔄"
      }).then(confirmed => {
        if (confirmed) performReset()
      })
    } else {
      if (confirm("Reset all checkboxes for this grocery list? This clears them for everyone in the household.")) {
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
    const weekLabel = this.rangeLabelValue || "Shopping List"
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
