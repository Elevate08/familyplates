import { Controller } from "@hotwired/stimulus"

// Report this device's IANA zone once. The server refuses to overwrite one that
// exists. A browser that cannot answer stays quiet; UTC remains the fallback.
export default class extends Controller {
  static values = { url: String }

  connect() {
    const zone = this.detected
    if (!zone) return

    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
      },
      body: JSON.stringify({ time_zone: zone })
    }).catch(() => {
      // Offline, or the request was refused. Nothing to recover: the zone is a
      // convenience, and the next page load asks again.
    })
  }

  get detected() {
    try {
      return Intl.DateTimeFormat().resolvedOptions().timeZone
    } catch (error) {
      return null
    }
  }
}
