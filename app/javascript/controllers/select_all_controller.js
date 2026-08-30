import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "countDisplay"]

  connect() {
    this.updateCount()
  }

  selectAll(event) {
    if (event) event.preventDefault()
    this.checkboxTargets.forEach(cb => {
      cb.checked = true
    })
    this.updateCount()
  }

  deselectAll(event) {
    if (event) event.preventDefault()
    this.checkboxTargets.forEach(cb => {
      cb.checked = false
    })
    this.updateCount()
  }

  toggle(event) {
    this.updateCount()
  }

  updateCount() {
    if (!this.hasCountDisplayTarget) return
    const checkedCount = this.checkboxTargets.filter(cb => cb.checked).length
    const totalCount = this.checkboxTargets.length
    this.countDisplayTarget.textContent = `${checkedCount} of ${totalCount} selected`
  }
}
