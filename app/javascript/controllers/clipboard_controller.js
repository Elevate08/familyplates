import { Controller } from "@hotwired/stimulus"

// Replaces an inline onclick that read an input and called alert(). Also drops
// the alert() for an inline confirmation on the button itself.
export default class extends Controller {
  static targets = ["source", "feedback"]
  static values = { confirmation: { type: String, default: "Copied!" } }

  async copy() {
    if (!this.hasSourceTarget) return

    try {
      await navigator.clipboard.writeText(this.sourceTarget.value)
      this.showConfirmation()
    } catch {
      this.sourceTarget.select()
    }
  }

  showConfirmation() {
    if (!this.hasFeedbackTarget) return

    const original = this.feedbackTarget.textContent
    this.feedbackTarget.textContent = this.confirmationValue
    setTimeout(() => { this.feedbackTarget.textContent = original }, 2000)
  }
}
