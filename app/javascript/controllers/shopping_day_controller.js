import { Controller } from "@hotwired/stimulus"

// Weekly and fortnightly shop on a weekday. Monthly shops on a day of the
// month. The frequency select swaps which of those two fields is submitted.
export default class extends Controller {
  static targets = [ "frequency", "weekday", "monthday" ]

  connect() {
    this.toggle()
  }

  toggle() {
    const monthly = this.frequencyTarget.value === "monthly"
    this.setActive(this.weekdayTarget, !monthly)
    this.setActive(this.monthdayTarget, monthly)
  }

  setActive(element, active) {
    element.hidden = !active
    element.querySelectorAll("select, input").forEach((field) => {
      field.disabled = !active
    })
  }
}
