import { Controller } from "@hotwired/stimulus"

// Reports this device's IANA time zone once, so the household does not have to
// be told what o'clock it is before "cooking now" can mean anything.
//
// Only rendered when the household has no zone recorded, and the server refuses
// to overwrite one that exists, so this runs at most once per install in
// practice. A browser that cannot answer simply stays quiet - UTC remains the
// fallback and the settings form is still there.
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
