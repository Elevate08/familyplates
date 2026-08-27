import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]

  open(event) {
    if (event) event.preventDefault()
    if (this.hasDialogTarget) {
      this.dialogTarget.classList.remove("hidden")
      this.dialogTarget.classList.add("flex")
    }
  }

  close(event) {
    if (event) event.preventDefault()
    if (this.hasDialogTarget) {
      this.dialogTarget.classList.add("hidden")
      this.dialogTarget.classList.remove("flex")
    }
  }

  handleKeydown(event) {
    if (event.key === "Escape") {
      this.close()
    }
  }
}
