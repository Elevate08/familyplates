import { Controller } from "@hotwired/stimulus"
import { el, replaceChildren } from "helpers/dom"

export default class extends Controller {
  static targets = [
    "testButton",
    "testStatus",
    "calendarIdInput",
    "syncButton",
    "syncContainer",
    "progressBar",
    "progressText",
    "syncSuccess"
  ]
  static values = {
    testUrl: String,
    syncUrl: String
  }

  async testConnection(event) {
    if (event) event.preventDefault()

    if (this.testTimeout) clearTimeout(this.testTimeout)
    const calendarId = this.hasCalendarIdInputTarget ? this.calendarIdInputTarget.value : ""
    const token = document.querySelector('meta[name="csrf-token"]')?.content

    if (this.hasTestButtonTarget) this.testButtonTarget.disabled = true
    if (this.hasTestStatusTarget) {
      this.testStatusTarget.classList.remove("hidden", "opacity-0")
      this.testStatusTarget.classList.add("opacity-100", "transition-opacity", "duration-500")
      replaceChildren(this.testStatusTarget,
        el("div", { className: "inline-flex items-center gap-2 px-3 py-1.5 rounded-xl bg-blue-50 border border-blue-200 text-blue-800 text-xs font-semibold animate-in fade-in" }, [
          el("span", { className: "relative flex h-2.5 w-2.5" }, [
            el("span", { className: "animate-ping absolute inline-flex h-full w-full rounded-full bg-blue-400 opacity-75" }),
            el("span", { className: "relative inline-flex rounded-full h-2.5 w-2.5 bg-blue-600" })
          ]),
          el("span", { className: "animate-pulse", text: "Testing connection to Google Calendar..." })
        ])
      )
    }

    try {
      const response = await fetch(this.testUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": token
        },
        body: JSON.stringify({ google_calendar_id: calendarId })
      })

      const data = await response.json()

      if (data.success) {
        this.renderStatus(this.testStatusTarget, "emerald", `Connected: "${data.summary || "Google Calendar"}"`)
      } else {
        this.renderStatus(this.testStatusTarget, "rose", `Connection Failed: ${data.error || "Check Calendar ID and Service Account share permissions."}`)
      }
    } catch (err) {
      if (this.hasTestStatusTarget) {
        this.renderStatus(this.testStatusTarget, "rose", "Network error testing connection.")
      }
    } finally {
      if (this.hasTestButtonTarget) this.testButtonTarget.disabled = false
      if (this.hasTestStatusTarget) {
        this.testTimeout = setTimeout(() => {
          this.testStatusTarget.classList.remove("opacity-100")
          this.testStatusTarget.classList.add("opacity-0")
          setTimeout(() => this.testStatusTarget.classList.add("hidden"), 500)
        }, 4000)
      }
    }
  }

  async syncPlan(event) {
    if (event) event.preventDefault()

    if (this.syncTimeout) clearTimeout(this.syncTimeout)
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (this.hasSyncButtonTarget) this.syncButtonTarget.disabled = true

    if (this.hasSyncContainerTarget) {
      this.syncContainerTarget.classList.remove("hidden", "opacity-0")
      this.syncContainerTarget.classList.add("opacity-100", "transition-opacity", "duration-500")
    }
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.style.width = "15%"
      this.progressBarTarget.classList.remove("bg-emerald-500", "bg-rose-500")
      this.progressBarTarget.classList.add("bg-blue-600")
    }
    if (this.hasProgressTextTarget) {
      this.progressTextTarget.textContent = "Connecting to Google Calendar..."
    }

    // Step-up animation while request is in flight
    let progress = 15
    const interval = setInterval(() => {
      if (progress < 85) {
        progress += Math.floor(Math.random() * 15) + 10
        if (progress > 85) progress = 85
        if (this.hasProgressBarTarget) this.progressBarTarget.style.width = `${progress}%`
        if (this.hasProgressTextTarget) this.progressTextTarget.textContent = `Syncing meal slots to Google Calendar... (${progress}%)`
      }
    }, 200)

    try {
      const response = await fetch(this.syncUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": token
        }
      })

      clearInterval(interval)
      const data = await response.json()

      if (data.success) {
        if (this.hasProgressBarTarget) {
          this.progressBarTarget.style.width = "100%"
          this.progressBarTarget.classList.remove("bg-blue-600")
          this.progressBarTarget.classList.add("bg-emerald-500")
        }
        if (this.hasProgressTextTarget) {
          replaceChildren(this.progressTextTarget, el("span", { className: "text-emerald-700 font-bold", text: `✅ ${data.message || "Successfully synced meal slots to Google Calendar!"}` }))
        }
      } else {
        if (this.hasProgressBarTarget) {
          this.progressBarTarget.style.width = "100%"
          this.progressBarTarget.classList.remove("bg-blue-600")
          this.progressBarTarget.classList.add("bg-rose-500")
        }
        if (this.hasProgressTextTarget) {
          replaceChildren(this.progressTextTarget, el("span", { className: "text-rose-700 font-bold", text: `❌ Sync failed: ${data.error || "Please check configuration in Admin settings."}` }))
        }
      }
    } catch (err) {
      clearInterval(interval)
      if (this.hasProgressBarTarget) {
        this.progressBarTarget.style.width = "100%"
        this.progressBarTarget.classList.remove("bg-blue-600")
        this.progressBarTarget.classList.add("bg-rose-500")
      }
      if (this.hasProgressTextTarget) {
        replaceChildren(this.progressTextTarget, el("span", { className: "text-rose-700 font-bold", text: "❌ Network error during sync." }))
      }
    } finally {
      if (this.hasSyncButtonTarget) this.syncButtonTarget.disabled = false
      if (this.hasSyncContainerTarget) {
        this.syncTimeout = setTimeout(() => {
          this.syncContainerTarget.classList.remove("opacity-100")
          this.syncContainerTarget.classList.add("opacity-0")
          setTimeout(() => this.syncContainerTarget.classList.add("hidden"), 500)
        }, 4000)
      }
    }
  }

  // Google's API returns the summary and error strings, so they are external
  // content and must land as text rather than markup.
  renderStatus(target, tone, message) {
    replaceChildren(target,
      el("div", { className: `inline-flex items-center gap-2 px-3 py-1.5 rounded-xl bg-${tone}-50 border border-${tone}-200 text-${tone}-800 text-xs font-bold animate-in fade-in` }, [
        el("span", { className: `w-2.5 h-2.5 rounded-full bg-${tone}-500 shadow-sm` }),
        el("span", { text: message })
      ])
    )
  }
}
