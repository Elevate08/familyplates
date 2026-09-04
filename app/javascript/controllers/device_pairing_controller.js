import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "error", "container"]
  static values = {
    tokenUrl: { type: String, default: "/pair/token" },
    deviceCode: String,
    interval: { type: Number, default: 5 },
    redirectUrl: { type: String, default: "/" }
  }

  connect() {
    this.startPolling()
  }

  disconnect() {
    this.stopPolling()
  }

  startPolling() {
    this.stopPolling()
    const ms = Math.max(this.intervalValue, 2) * 1000
    this.timer = setInterval(() => this.poll(), ms)
  }

  stopPolling() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = null
    }
  }

  resetTimer() {
    this.stopPolling()
    this.startPolling()
  }

  async poll() {
    if (!this.deviceCodeValue) return

    try {
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
      const headers = {
        "Content-Type": "application/json",
        "Accept": "application/json"
      }
      if (csrfToken) headers["X-CSRF-Token"] = csrfToken

      const response = await fetch(this.tokenUrlValue, {
        method: "POST",
        headers: headers,
        body: JSON.stringify({ device_code: this.deviceCodeValue })
      })

      const data = await response.json()

      if (response.ok) {
        this.stopPolling()
        if (this.hasStatusTarget) {
          this.statusTarget.textContent = "Paired! Connecting to kitchen..."
        }
        window.location.href = data.redirect_url || this.redirectUrlValue
        return
      }

      if (data.error === "slow_down") {
        this.intervalValue = Math.min(this.intervalValue + 5, 30)
        this.resetTimer()
      } else if (data.error === "expired_token") {
        this.stopPolling()
        this.showError("This pairing code has expired. Please refresh the page to generate a new code.")
      } else if (data.error === "access_denied") {
        this.stopPolling()
        this.showError("The pairing request was denied on the approving device.")
      } else if (data.error !== "authorization_pending") {
        this.stopPolling()
        this.showError(data.error_description || "An error occurred during pairing.")
      }
    } catch (e) {
      // Network hiccup, keep polling
    }
  }

  showError(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.classList.remove("hidden")
    }
    if (this.hasStatusTarget) {
      this.statusTarget.classList.add("hidden")
    }
  }
}
