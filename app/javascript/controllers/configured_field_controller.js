import { Controller } from "@hotwired/stimulus"

// A stored secret is never shown back, so the field stays empty and a badge says one is set.
// The badge hides once the field is focused or has text.
export default class extends Controller {
  static targets = ["input", "indicator"]

  connect() {
    this.update()
  }

  hide() {
    if (this.hasIndicatorTarget) this.indicatorTarget.hidden = true
  }

  update() {
    if (!this.hasIndicatorTarget) return

    const focused = this.hasInputTarget && document.activeElement === this.inputTarget
    const filled = this.hasInputTarget && this.inputTarget.value.length > 0

    this.indicatorTarget.hidden = focused || filled
  }
}
