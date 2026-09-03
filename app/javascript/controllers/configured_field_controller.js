import { Controller } from "@hotwired/stimulus"

// A secret that is stored can never be shown back, so the field is always empty
// and a placeholder alone cannot say "there is one, leave this alone". This
// floats a "Configured" badge over the field instead, and gets it out of the way
// the moment the field is focused or has anything typed in it.
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
