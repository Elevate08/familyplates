import { Controller } from "@hotwired/stimulus"

// Replaces onclick="this.parentElement.remove()" on flash messages. Inline
// handlers cannot be allowed by a nonce - only by 'unsafe-inline', which is the
// thing the CSP exists to withhold.
export default class extends Controller {
  remove() {
    this.element.remove()
  }
}
