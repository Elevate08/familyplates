import { Controller } from "@hotwired/stimulus"

// Inline onclick cannot carry a CSP nonce. Removing the flash stays in this controller.
export default class extends Controller {
  remove() {
    this.element.remove()
  }
}
