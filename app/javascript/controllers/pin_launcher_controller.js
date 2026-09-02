import { Controller } from "@hotwired/stimulus"

// Replaces onclick="openPinModal('1', 'Dad', '#3B82F6', 'D')" and its
// openNavPinModal twin. The modal logic itself is unchanged and still lives in
// the nonced inline script beside each modal; this only carries the arguments
// across, which is what the inline attribute was doing.
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
