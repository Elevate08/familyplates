import { Controller } from "@hotwired/stimulus"

// Keep the screen awake in Cook Mode. Missing API or a lock dropped when the
// tab hides is normal, not an error: the indicator reports which, and the view continues.
export default class extends Controller {
  static targets = ["indicator", "label"]
  static values = {
    heldText: { type: String, default: "Screen stays on" },
    releasedText: { type: String, default: "Screen may dim" }
  }

  connect() {
    this.sentinel = null
    this.boundVisibilityChange = this.visibilityChange.bind(this)
    document.addEventListener("visibilitychange", this.boundVisibilityChange)
    this.request()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.boundVisibilityChange)
    this.release()
  }

  get supported() {
    return "wakeLock" in navigator
  }

  async request() {
    if (!this.supported || this.sentinel) return this.render()

    try {
      this.sentinel = await navigator.wakeLock.request("screen")
      // The system releases the lock on its own when the tab is hidden; drop the
      // stale sentinel so the next visibility change asks for a fresh one.
      this.sentinel.addEventListener("release", () => {
        this.sentinel = null
        this.render()
      })
    } catch (error) {
      this.sentinel = null
    }

    this.render()
  }

  release() {
    if (!this.sentinel) return

    const sentinel = this.sentinel
    this.sentinel = null
    sentinel.release().catch(() => {})
  }

  visibilityChange() {
    if (document.visibilityState === "visible") {
      this.request()
    } else {
      this.render()
    }
  }

  render() {
    if (!this.hasIndicatorTarget) return

    const held = Boolean(this.sentinel)
    this.indicatorTarget.classList.toggle("text-emerald-300", held)
    this.indicatorTarget.classList.toggle("text-slate-500", !held)

    if (this.hasLabelTarget) {
      this.labelTarget.textContent = held ? this.heldTextValue : this.releasedTextValue
    }
  }
}
