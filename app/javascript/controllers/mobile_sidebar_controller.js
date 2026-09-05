import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["drawer", "backdrop"]

  toggle() {
    if (this.hasDrawerTarget) {
      this.drawerTarget.classList.toggle("hidden")
    }
    if (this.hasBackdropTarget) {
      this.backdropTarget.classList.toggle("hidden")
    }
  }

  close() {
    if (this.hasDrawerTarget) {
      this.drawerTarget.classList.add("hidden")
    }
    if (this.hasBackdropTarget) {
      this.backdropTarget.classList.add("hidden")
    }
  }
}
