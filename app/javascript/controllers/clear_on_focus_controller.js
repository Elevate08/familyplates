import { Controller } from "@hotwired/stimulus"

// Replaces onfocus="this.value = '';" on the onboarding PIN field, which is
// prefilled with a suggested 1234 and should empty when the user types their own.
export default class extends Controller {
  clear() {
    this.element.value = ""
  }
}
