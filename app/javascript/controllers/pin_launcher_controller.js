import { Controller } from "@hotwired/stimulus"

// Carries the member into the nonced inline modal script. Inline onclick cannot carry a CSP nonce.
export default class extends Controller {
  static values = {
    memberId: String,
    memberName: String,
    memberColor: String,
    memberInitial: String,
    modal: { type: String, default: "select" } // "select" or "nav"
  }

  open(event) {
    event.preventDefault()

    const opener = this.modalValue === "nav" ? window.openNavPinModal : window.openPinModal
    if (typeof opener !== "function") return

    opener(this.memberIdValue, this.memberNameValue, this.memberColorValue, this.memberInitialValue)
  }

  close(event) {
    event.preventDefault()

    const closer = this.modalValue === "nav" ? window.closeNavPinModal : window.closePinModal
    if (typeof closer === "function") closer()
  }
}
